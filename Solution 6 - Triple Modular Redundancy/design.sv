// =============================================================================
// Solution 6: Triple Modular Redundancy (TMR) Authentication FSM
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

// Top-Level Triple Modular Redundancy (TMR) Module
module auth_fsm_tmr (
    input clk,
    input rst_n,
    input auth_in,
    input [11:0] fault_mask, // [3:0]: FSM1 (A), [7:4]: FSM2 (B), [11:8]: FSM3 (C)
    output access_granted,
    output auth_A,
    output auth_B,
    output auth_C,
    output [3:0] state_A,
    output [3:0] state_B,
    output [3:0] state_C,
    output disagreement_detected
);

    // Module 1 (A)
    auth_fsm_core fsm_A (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[3:0]),
        .state_out(state_A),
        .auth_out(auth_A)
    );

    // Module 2 (B)
    auth_fsm_core fsm_B (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[7:4]),
        .state_out(state_B),
        .auth_out(auth_B)
    );

    // Module 3 (C)
    auth_fsm_core fsm_C (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask[11:8]),
        .state_out(state_C),
        .auth_out(auth_C)
    );

    // Majority Voting Logic: AB + BC + AC
    assign access_granted = (auth_A & auth_B) | (auth_B & auth_C) | (auth_A & auth_C);

    // Diagnostic Disagreement Flag (asserts if any module diverges)
    assign disagreement_detected = !((state_A == state_B) && (state_B == state_C));

endmodule
