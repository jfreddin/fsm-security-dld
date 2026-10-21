`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [11:0] fault_mask; // [3:0]: A, [7:4]: B, [11:8]: C

    wire access_granted;
    wire auth_A;
    wire auth_B;
    wire auth_C;
    wire [3:0] state_A;
    wire [3:0] state_B;
    wire [3:0] state_C;
    wire disagreement_detected;

    auth_fsm_tmr uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .auth_A(auth_A),
        .auth_B(auth_B),
        .auth_C(auth_C),
        .state_A(state_A),
        .state_B(state_B),
        .state_C(state_C),
        .disagreement_detected(disagreement_detected)
    );

    // 100 MHz Clock (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Apply input and fault mask for 1 full clock cycle
    task apply_stimulus(input bit in_val, input [11:0] mask);
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
            fault_mask = 12'h000;
            repeat(2) @(negedge clk);
            rst_n      = 1;
        end
    endtask

    initial begin
        $dumpfile("fsm_simulation.vcd");
        $dumpvars(0, testbench);

        $monitor("Time=%3t ns | in=%b mask=%h | sA=%b (A=%b) sB=%b (B=%b) sC=%b (C=%b) | disag=%b | TMR_Auth=%b", 
                 $time, auth_in, fault_mask, state_A, auth_A, state_B, auth_B, state_C, auth_C, 
                 disagreement_detected, access_granted);

        // =========================================================================
        // SCENARIO 1: Correct Passcode (1010) - Clean Run (Unanimous 3-0 Consensus)
        // =========================================================================
        $display("\n=========================================================================");
        $display("SCENARIO 1: Correct Passcode (1010) - Unanimous Consensus (A=1, B=1, C=1)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1 -> GOT_1   (0100)
        apply_stimulus(1'b0, 12'h000); // Bit 2: 0 -> GOT_10  (0101)
        apply_stimulus(1'b1, 12'h000); // Bit 3: 1 -> GOT_101 (0110)
        apply_stimulus(1'b0, 12'h000); // Bit 4: 0 -> SUCCESS (0111)

        apply_stimulus(1'b0, 12'h000); // Hold
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && auth_A == 1'b1 && auth_B == 1'b1 && auth_C == 1'b1)
            $display(">> SCENARIO 1 PASSED: Unanimous agreement: AB + BC + AC = 1, Access Granted!\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =========================================================================
        // SCENARIO 2: Single-Module Failure Masked (Fault Tolerance)
        // Legitimate user inputs 1010. Module A suffers a bit flip (mask=12'h004)
        // Modules B and C remain correct: A=0, B=1, C=1 => AB+BC+AC = 1!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 2: Module A Glitched -> TMR Masks Fault: AB+BC+AC = 1");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1
        apply_stimulus(1'b0, 12'h004); // Bit 2: 0 with bit-flip injected into Module A!
        apply_stimulus(1'b1, 12'h000); // Bit 3: 1
        apply_stimulus(1'b0, 12'h000); // Bit 4: 0

        apply_stimulus(1'b0, 12'h000);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && auth_A == 1'b0 && auth_B == 1'b1 && auth_C == 1'b1)
            $display(">> SCENARIO 2 PASSED: Module A failed (0), but B & C consensus (1 & 1) preserved Access Granted!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =========================================================================
        // SCENARIO 3: Attacker Attempts Single-Module Bypass on Invalid Passcode
        // Attacker enters wrong passcode (1110) and glitches Module A to SUCCESS (0111).
        // Since next_state from ERR_3 is LOCKED (0011), fault mask 4'h4 flips state_A to SUCCESS (0111).
        // Modules B & C are in LOCKED (0011, B=0, C=0). AB + BC + AC = 0! Bypass blocked!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 3: Attacker Glitches Module A to SUCCESS -> TMR Blocks Bypass!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1 (correct)
        apply_stimulus(1'b1, 12'h000); // Bit 2: 1 (wrong)
        apply_stimulus(1'b1, 12'h000); // Bit 3: 1
        apply_stimulus(1'b0, 12'h004); // Glitch Module A into SUCCESS (0011 ^ 0100 = 0111)

        // Evaluate while glitch has forced Module A to SUCCESS
        if (access_granted == 1'b0 && auth_A == 1'b1 && auth_B == 1'b0 && auth_C == 1'b0)
            $display(">> SCENARIO 3 PASSED: Module A forced to SUCCESS (auth_A=1), but TMR majority vote prevented bypass (access_granted=0)!\n");
        else
            $display(">> SCENARIO 3 FAILED: Security breach! Bypass was not thwarted!\n");

        apply_stimulus(1'b0, 12'h000);
        repeat(2) @(negedge clk);

        // =========================================================================
        // SCENARIO 4: Normal Wrong Passcode (1110) - Unanimous Lockout
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 4: Wrong Passcode (1110) - Unanimous Lockout (A=0, B=0, C=0)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 12'h000); // Bit 1: 1
        apply_stimulus(1'b1, 12'h000); // Bit 2: 1 (wrong)
        apply_stimulus(1'b1, 12'h000); // Bit 3: 1
        apply_stimulus(1'b0, 12'h000); // Bit 4: 0

        apply_stimulus(1'b0, 12'h000);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b0 && auth_A == 1'b0 && auth_B == 1'b0 && auth_C == 1'b0)
            $display(">> SCENARIO 4 PASSED: All 3 modules unanimously locked out wrong passcode!\n");
        else
            $display(">> SCENARIO 4 FAILED\n");

        $display("=========================================================================");
        $display("All Solution 6 Test Scenarios Completed Successfully!");
        $display("=========================================================================\n");
        $finish;
    end

endmodule
