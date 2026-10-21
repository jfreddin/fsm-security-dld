module auth_fsm (
    input clk,
    input rst_n,
    input auth_in,
    input [4:0] fault_mask, // 5-bit mask: supports clean bit-flips (0/1) AND laser metastability ('x')
    output reg access_granted,
    output [3:0] state_out,
    output parity_out,
    output metastable_detected,
    output alarm_out
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

    parameter EXPECTED_PARITY = 1'b0;

    reg [3:0] state, next_state;
    reg parity;
    reg alarm;

    wire is_metastable = $isunknown({parity, state});

    assign state_out           = state;
    assign parity_out          = parity;
    assign metastable_detected = is_metastable;
    assign alarm_out           = alarm;

    always @(*) begin
        if (alarm || is_metastable) begin
            next_state = LOCKED;
        end else begin
            case (state)
                IDLE:    next_state = (auth_in) ? GOT_1   : ERR_1;
                GOT_1:   next_state = (!auth_in)? GOT_10  : ERR_2;
                GOT_10:  next_state = (auth_in) ? GOT_101 : ERR_3;
                GOT_101: next_state = (!auth_in)? SUCCESS : LOCKED;
                
                ERR_1:   next_state = ERR_2;
                ERR_2:   next_state = ERR_3;
                ERR_3:   next_state = LOCKED;
                
                SUCCESS: next_state = SUCCESS;
                LOCKED:  next_state = LOCKED;
                
                default: next_state = LOCKED;
            endcase
        end
    end

    // Sequential logic: 4 DFFs for state + 1 DFF for parity + 1 DFF for sticky alarm
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= IDLE;
            parity <= 1'b0;
            alarm  <= 1'b0;
        end else begin
            // XOR with fault_mask: if fault_mask bit is 'x', flip-flop stores 'x' (metastable)!
            state  <= (next_state ^ fault_mask[3:0]);
            parity <= (parity ^ auth_in) ^ fault_mask[4];
            
            // Trip and latch alarm if metastability or corrupted state is detected
            if (is_metastable)
                alarm <= 1'b1;
        end
    end

    always @(*) begin
        if (!alarm && !is_metastable && (state == SUCCESS) && (parity == EXPECTED_PARITY))
            access_granted = 1'b1;
        else
            access_granted = 1'b0;
    end

endmodule
