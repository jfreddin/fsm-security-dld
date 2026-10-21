module auth_fsm (
    input clk,
    input rst_n,
    input auth_in,
    input [4:0] fault_mask, // 5-bit fault mask injecting directly into 5-bit state register
    output reg access_granted,
    output [4:0] state_out,
    output in_between_trap_out
);

    parameter IDLE        = 5'b00000;
    parameter GOT_1       = 5'b00011;
    parameter GOT_10      = 5'b00101;
    parameter GOT_101     = 5'b00110;
    parameter SUCCESS     = 5'b01001;
    parameter ERR_1       = 5'b01010;
    parameter ERR_2       = 5'b01100;
    parameter ERR_3       = 5'b10001;
    parameter LOCKED      = 5'b10010;
    parameter TRAP_LOCKED = 5'b11110; // Dedicated lock state for in-between errors

    reg [4:0] state, next_state;
    reg is_in_between;

    assign state_out            = state;
    assign in_between_trap_out  = is_in_between;

    // Combinational next-state logic
    always @(*) begin
        is_in_between = 1'b0;
        case (state)
            IDLE:        next_state = (auth_in) ? GOT_1   : ERR_1;
            GOT_1:       next_state = (!auth_in)? GOT_10  : ERR_2;
            GOT_10:      next_state = (auth_in) ? GOT_101 : ERR_3;
            GOT_101:     next_state = (!auth_in)? SUCCESS : LOCKED;
            
            // Constant-time error progression pipeline
            ERR_1:       next_state = ERR_2;
            ERR_2:       next_state = ERR_3;
            ERR_3:       next_state = LOCKED;
            
            // Terminal states
            SUCCESS:     next_state = SUCCESS;
            LOCKED:      next_state = LOCKED;
            TRAP_LOCKED: next_state = TRAP_LOCKED; // Stay locked until cycle reset
            
            // ANY in-between state caused by a bit flip immediately gets trapped!
            default: begin
                is_in_between = 1'b1;
                next_state    = TRAP_LOCKED;
            end
        endcase
    end

    // Sequential state register update: 5 D flip-flops, NO separate parity flip-flop!
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= (next_state ^ fault_mask);
    end

    // Output logic: Access is granted ONLY when in the authentic SUCCESS state.
    // In-between states and trap states immediately deauthenticate (0).
    always @(*) begin
        if (state == SUCCESS)
            access_granted = 1'b1;
        else
            access_granted = 1'b0;
    end

endmodule
