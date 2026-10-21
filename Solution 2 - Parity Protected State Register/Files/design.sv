module auth_fsm (
    input clk,
    input rst_n,
    input auth_in,
    input [4:0] fault_mask, // [4]: state_parity, [3:0]: state[3:0]. Supports 0, 1, and 'x' (metastable)
    output reg access_granted,
    output [3:0] state_out,
    output state_parity_out,
    output parity_valid_out,
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

    reg [3:0] state, next_state;
    reg state_parity;
    reg alarm;

    // =========================================================================
    // METASTABILITY / ANALOG GLITCH DETECTOR
    // Detects if laser injection induced an 'x' on state FFs or parity FF
    // =========================================================================
    wire is_metastable = $isunknown({state_parity, state});

    // Next-state parity prediction:
    wire next_state_parity = ^next_state;

    // Hardware Invariant Check: Must be non-metastable AND state parity must match
    wire state_parity_valid = (!is_metastable) && (^state === state_parity);

    assign state_out           = state;
    assign state_parity_out    = state_parity;
    assign parity_valid_out    = state_parity_valid;
    assign metastable_detected = is_metastable;
    assign alarm_out           = alarm;

    // Combinational next-state logic
    always @(*) begin
        if (alarm || is_metastable) begin
            next_state = LOCKED; // Security trip: immediately lock if alarm triggered
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
                
                default: next_state = IDLE;
            endcase
        end
    end

    // Sequential logic with parity protection & sticky alarm latch
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            state_parity <= ^IDLE; // Parity of 4'b0000 is 0
            alarm        <= 1'b0;
        end else begin
            state        <= (next_state ^ fault_mask[3:0]);
            state_parity <= (next_state_parity ^ fault_mask[4]);
            
            // Latch security alarm if parity is broken OR metastability is detected
            if (!state_parity_valid || is_metastable)
                alarm <= 1'b1;
        end
    end

    // Output logic: Access is granted ONLY if healthy, not metastable, and state matches
    always @(*) begin
        if (!alarm && !is_metastable && (state == SUCCESS) && state_parity_valid)
            access_granted = 1'b1;
        else
            access_granted = 1'b0;
    end

endmodule
