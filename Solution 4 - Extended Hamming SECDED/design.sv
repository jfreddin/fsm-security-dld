module auth_fsm (
    input clk,
    input rst_n,
    input auth_in,
    input [7:0] fault_mask, // [7:4]: parity bits {p0, p3, p2, p1}, [3:0]: state bits
    output reg access_granted,
    output [3:0] raw_state_out,
    output [3:0] corrected_state_out,
    output [3:0] hamming_parity_out,
    output single_error_detected,
    output double_error_detected,
    output corrupted_state_detected,
    output deauth_latched_out
);

    // Standard FSM state parameters
    parameter IDLE    = 4'b0000;
    parameter GOT_1   = 4'b0100;
    parameter GOT_10  = 4'b0101;
    parameter GOT_101 = 4'b0110;
    parameter SUCCESS = 4'b0111;
    parameter ERR_1   = 4'b1000;
    parameter ERR_2   = 4'b1001;
    parameter ERR_3   = 4'b1010;
    parameter LOCKED  = 4'b0011;

    reg [3:0] state;
    reg [3:0] hamming_parity; // {p0, p3, p2, p1}
    reg [3:0] next_state;
    reg deauth_latched;

    // -------------------------------------------------------------
    // Metastability Detection (IEEE 4-state 'x' from laser attacks)
    // -------------------------------------------------------------
    wire is_metastable = $isunknown({hamming_parity, state});

    // -------------------------------------------------------------
    // Extended Hamming (SECDED 8,4) Generator for Next State
    // d[0]=state[0], d[1]=state[1], d[2]=state[2], d[3]=state[3]
    // -------------------------------------------------------------
    wire np1 = next_state[0] ^ next_state[1] ^ next_state[3];
    wire np2 = next_state[0] ^ next_state[2] ^ next_state[3];
    wire np3 = next_state[1] ^ next_state[2] ^ next_state[3];
    wire np0 = np1 ^ np2 ^ np3 ^ next_state[0] ^ next_state[1] ^ next_state[2] ^ next_state[3];
    wire [3:0] next_parity = {np0, np3, np2, np1};

    // -------------------------------------------------------------
    // Syndrome & Parity Check on Current Registered State
    // -------------------------------------------------------------
    wire s1 = hamming_parity[0] ^ state[0] ^ state[1] ^ state[3];
    wire s2 = hamming_parity[1] ^ state[0] ^ state[2] ^ state[3];
    wire s3 = hamming_parity[2] ^ state[1] ^ state[2] ^ state[3];
    wire [2:0] syndrome = {s3, s2, s1};

    wire overall_parity = hamming_parity[3] ^ hamming_parity[2] ^ hamming_parity[1] ^ hamming_parity[0] ^
                         state[3] ^ state[2] ^ state[1] ^ state[0];

    // Single-bit vs Double-bit error classification
    wire s_err = (!is_metastable) && (overall_parity == 1'b1);
    wire d_err = (!is_metastable) && (syndrome != 3'b000) && (overall_parity == 1'b0);

    // Single-Bit Error Correction (SECDED)
    reg [3:0] corrected_state;
    always @(*) begin
        corrected_state = state;
        if (s_err) begin
            case (syndrome)
                3'b011: corrected_state[0] = ~state[0]; // Bit 0 corrected
                3'b101: corrected_state[1] = ~state[1]; // Bit 1 corrected
                3'b110: corrected_state[2] = ~state[2]; // Bit 2 corrected
                3'b111: corrected_state[3] = ~state[3]; // Bit 3 corrected
                default: corrected_state = state;      // Parity bit error only
            endcase
        end
    end

    // -------------------------------------------------------------
    // Corrupted / Unmapped State Detection
    // -------------------------------------------------------------
    reg is_valid_state;
    always @(*) begin
        case (corrected_state)
            IDLE, GOT_1, GOT_10, GOT_101, SUCCESS,
            ERR_1, ERR_2, ERR_3, LOCKED: is_valid_state = 1'b1;
            default:                      is_valid_state = 1'b0;
        endcase
    end
    wire corrupted_state = (!is_metastable) && (!is_valid_state);

    // Outputs
    assign raw_state_out            = state;
    assign corrected_state_out      = corrected_state;
    assign hamming_parity_out       = hamming_parity;
    assign single_error_detected    = s_err;
    assign double_error_detected    = d_err;
    assign corrupted_state_detected = corrupted_state;
    assign deauth_latched_out       = deauth_latched;

    // -------------------------------------------------------------
    // Next-State Combinational Logic (using corrected_state)
    // -------------------------------------------------------------
    always @(*) begin
        if (deauth_latched || is_metastable) begin
            next_state = LOCKED;
        end else begin
            case (corrected_state)
                IDLE:    next_state = (auth_in)  ? GOT_1   : ERR_1;
                GOT_1:   next_state = (!auth_in) ? GOT_10  : ERR_2;
                GOT_10:  next_state = (auth_in)  ? GOT_101 : ERR_3;
                GOT_101: next_state = (!auth_in) ? SUCCESS : LOCKED;

                // Constant-time pipeline for wrong passcode
                ERR_1:   next_state = ERR_2;
                ERR_2:   next_state = ERR_3;
                ERR_3:   next_state = LOCKED;

                SUCCESS: next_state = SUCCESS;
                LOCKED:  next_state = LOCKED;

                default: next_state = LOCKED;
            endcase
        end
    end

    // -------------------------------------------------------------
    // Sequential Logic & Sticky Deauth Latch
    // -------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            hamming_parity <= 4'b0000; // Parity for IDLE(0000) is 0000
            deauth_latched <= 1'b0;
        end else begin
            // State & parity register update with fault injection mask
            state          <= (next_state ^ fault_mask[3:0]);
            hamming_parity <= (next_parity ^ fault_mask[7:4]);

            // Sticky deauth latch triggers on unrecoverable double errors, corrupted states, or metastability
            if (d_err || corrupted_state || is_metastable) begin
                deauth_latched <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------
    // Final Authentication Gate
    // -------------------------------------------------------------
    always @(*) begin
        if (!deauth_latched && !d_err && !is_metastable && !corrupted_state && (corrected_state == SUCCESS))
            access_granted = 1'b1;
        else
            access_granted = 1'b0;
    end

endmodule
