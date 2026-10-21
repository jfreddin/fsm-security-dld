// =============================================================================
// Solution 5: Dual Modular Redundancy (Dual Consensus) Authentication FSM
// =============================================================================

// Base Constant-Time 4-bit Sequence Detector Core
module auth_fsm_core (
    input clk,
    input rst_n,
    input auth_in,
    input [3:0] fault_mask,
    output [3:0] state_out,
    output auth_out
);

    parameter IDLE    = 4'b0000;
    parameter GOT_1   = 4'b0100;
    parameter GOT_10  = 4'b0101;
    parameter GOT_101 = 4'b0110;
    parameter SUCCESS = 4'b0111;
    parameter ERR_1   = 4'b1000;
    parameter ERR_2   = 4'b1001;
    parameter ERR_3   = 4'b1010;
    parameter LOCKED  = 4'b0011;

    reg [3:0] state, next_state;

    assign state_out = state;
    assign auth_out  = (state == SUCCESS);

    always @(*) begin
        case (state)
            IDLE:    next_state = (auth_in)  ? GOT_1   : ERR_1;
            GOT_1:   next_state = (!auth_in) ? GOT_10  : ERR_2;
            GOT_10:  next_state = (auth_in)  ? GOT_101 : ERR_3;
            GOT_101: next_state = (!auth_in) ? SUCCESS : LOCKED;

            ERR_1:   next_state = ERR_2;
            ERR_2:   next_state = ERR_3;
            ERR_3:   next_state = LOCKED;

            SUCCESS: next_state = SUCCESS;
            LOCKED:  next_state = LOCKED;

            default: next_state = LOCKED;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= (next_state ^ fault_mask);
    end

endmodule

// Top-Level Dual Modular Redundancy (DMR) Module
module auth_fsm_dual (
    input clk,
    input rst_n,
    input auth_in,
    input [7:0] fault_mask, // [3:0]: FSM1 fault mask, [7:4]: FSM2 fault mask
    output reg access_granted,
    output [3:0] state_1_out,
    output [3:0] state_2_out,
    output auth_1_out,
    output auth_2_out,
    output mismatch_detected,
    output deauth_latched_out
);

    wire [3:0] state_1, state_2;
    wire auth_1, auth_2;
    reg deauth_latched;

    // Instance 1: Primary FSM
    auth_fsm_core fsm1 (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[3:0]),
        .state_out(state_1),
        .auth_out(auth_1)
    );

    // Instance 2: Redundant Secondary FSM
    auth_fsm_core fsm2 (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[7:4]),
        .state_out(state_2),
        .auth_out(auth_2)
    );

    // Metastability detector
    wire is_metastable = $isunknown({state_1, state_2});

    // Cross-comparison mismatch detection
    wire mismatch = (!is_metastable) && ((state_1 != state_2) || (auth_1 != auth_2));

    // Dual Consensus: 2-input AND gate between authentication signals
    wire consensus_auth = auth_1 & auth_2;

    assign state_1_out        = state_1;
    assign state_2_out        = state_2;
    assign auth_1_out         = auth_1;
    assign auth_2_out         = auth_2;
    assign mismatch_detected  = mismatch;
    assign deauth_latched_out = deauth_latched;

    // Sticky Deauth Latch
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            deauth_latched <= 1'b0;
        end else begin
            if (mismatch || is_metastable) begin
                deauth_latched <= 1'b1;
            end
        end
    end

    // Authentication Output Gate
    always @(*) begin
        if (!deauth_latched && !is_metastable && consensus_auth)
            access_granted = 1'b1;
        else
            access_granted = 1'b0;
    end

endmodule
