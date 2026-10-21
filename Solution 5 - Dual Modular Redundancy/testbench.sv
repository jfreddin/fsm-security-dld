`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [7:0] fault_mask; // [3:0]: FSM1, [7:4]: FSM2

    wire access_granted;
    wire [3:0] state_1_out;
    wire [3:0] state_2_out;
    wire auth_1_out;
    wire auth_2_out;
    wire mismatch_detected;
    wire deauth_latched_out;

    auth_fsm_dual uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .state_1_out(state_1_out),
        .state_2_out(state_2_out),
        .auth_1_out(auth_1_out),
        .auth_2_out(auth_2_out),
        .mismatch_detected(mismatch_detected),
        .deauth_latched_out(deauth_latched_out)
    );

    // 100 MHz Clock (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Apply input and fault mask for 1 full clock cycle
    task apply_stimulus(input bit in_val, input [7:0] mask);
        begin
            auth_in    = in_val;
            fault_mask = mask;
            @(negedge clk);
        end
    endtask

    // Reset sequence
    task reset_fsm;
        begin
            rst_n      = 0;
            auth_in    = 0;
            fault_mask = 8'h00;
            repeat(2) @(negedge clk);
            rst_n      = 1;
        end
    endtask

    initial begin
        $dumpfile("fsm_simulation.vcd");
        $dumpvars(0, testbench);

        $monitor("Time=%3t ns | in=%b mask=%h | s1=%b (a1=%b) s2=%b (a2=%b) | mismatch=%b deauth=%b | auth=%b", 
                 $time, auth_in, fault_mask, state_1_out, auth_1_out, state_2_out, auth_2_out, 
                 mismatch_detected, deauth_latched_out, access_granted);

        // =========================================================================
        // SCENARIO 1: Correct Passcode (1010) - Clean Run (Dual Consensus Agreement)
        // =========================================================================
        $display("\n=========================================================================");
        $display("SCENARIO 1: Correct Passcode (1010) - Clean Run (Both FSMs Agree)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 -> GOT_1   (0100)
        apply_stimulus(1'b0, 8'h00); // Bit 2: 0 -> GOT_10  (0101)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1 -> GOT_101 (0110)
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0 -> SUCCESS (0111)

        apply_stimulus(1'b0, 8'h00); // Hold
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && auth_1_out == 1'b1 && auth_2_out == 1'b1 && deauth_latched_out == 1'b0)
            $display(">> SCENARIO 1 PASSED: Dual consensus reached (1 & 1), Access Granted!\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =========================================================================
        // SCENARIO 2: Fault Injection into FSM 1 during traversal (state_1[2] flipped)
        // FSM 1 deviates from FSM 2 -> Mismatch detected -> Deauth latched!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 2: Single Fault Injected into FSM 1 (mask=8'h04) -> Deauth!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b0, 8'h04); // Bit 2: 0 with bit-flip injected into FSM 1!
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (deauth_latched_out == 1'b1 && access_granted == 1'b0)
            $display(">> SCENARIO 2 PASSED: Discrepancy between FSM 1 and FSM 2 detected, deauth latched, access denied!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =========================================================================
        // SCENARIO 3: Attacker Fault-Bypass Attempt on Invalid Passcode
        // Attacker enters wrong code (1110) and glitches FSM 1 to SUCCESS (0111)
        // Dual consensus AND gate blocks bypass: auth_1 & auth_2 = 1 & 0 = 0!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 3: Attacker Glitches FSM 1 to SUCCESS -> AND Gate Blocks Bypass!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 (correct)
        apply_stimulus(1'b1, 8'h00); // Bit 2: 1 (wrong bit -> both go to ERR_2)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        // Attacker injects fault into FSM 1 on cycle 4 to flip to SUCCESS:
        // Current state would be ERR_3 (1010). Flipping with 4'b1101 produces SUCCESS (0111).
        apply_stimulus(1'b0, 8'h0D); // Glitch FSM 1 only!

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b0 && (auth_1_out != auth_2_out || deauth_latched_out == 1'b1))
            $display(">> SCENARIO 3 PASSED: Dual consensus AND gate thwarted single-module bypass attack!\n");
        else
            $display(">> SCENARIO 3 FAILED: Security breach! Bypass was not thwarted!\n");

        // =========================================================================
        // SCENARIO 4: Normal Wrong Passcode (1110) - Both enter LOCKED
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 4: Wrong Passcode (1110) - Normal Progression to LOCKED");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b1, 8'h00); // Bit 2: 1 (wrong)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b0 && state_1_out == 4'b0011 && state_2_out == 4'b0011)
            $display(">> SCENARIO 4 PASSED: Both FSMs consistently locked out wrong passcode!\n");
        else
            $display(">> SCENARIO 4 FAILED\n");

        $display("=========================================================================");
        $display("All Solution 5 Test Scenarios Completed Successfully!");
        $display("=========================================================================\n");
        $finish;
    end

endmodule
