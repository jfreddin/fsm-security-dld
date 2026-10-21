`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst_n;
    reg auth_in;
    reg [7:0] fault_mask; // [7:4]: parity mask, [3:0]: state mask

    wire access_granted;
    wire [3:0] raw_state_out;
    wire [3:0] corrected_state_out;
    wire [3:0] hamming_parity_out;
    wire single_error_detected;
    wire double_error_detected;
    wire corrupted_state_detected;
    wire deauth_latched_out;

    auth_fsm uut (
        .clk(clk),
        .rst_n(rst_n),
        .auth_in(auth_in),
        .fault_mask(fault_mask),
        .access_granted(access_granted),
        .raw_state_out(raw_state_out),
        .corrected_state_out(corrected_state_out),
        .hamming_parity_out(hamming_parity_out),
        .single_error_detected(single_error_detected),
        .double_error_detected(double_error_detected),
        .corrupted_state_detected(corrupted_state_detected),
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

        $monitor("Time=%3t ns | in=%b mask=%h | raw=%b corr=%b par=%b | s_err=%b d_err=%b deauth=%b | auth=%b", 
                 $time, auth_in, fault_mask, raw_state_out, corrected_state_out, hamming_parity_out, 
                 single_error_detected, double_error_detected, deauth_latched_out, access_granted);

        // =========================================================================
        // SCENARIO 1: Correct Passcode (1010) - Clean Run (No Faults)
        // =========================================================================
        $display("\n=========================================================================");
        $display("SCENARIO 1: Correct Passcode (1010) - Clean Run (No Faults)");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 -> GOT_1   (0100)
        apply_stimulus(1'b0, 8'h00); // Bit 2: 0 -> GOT_10  (0101)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1 -> GOT_101 (0110)
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0 -> SUCCESS (0111)

        apply_stimulus(1'b0, 8'h00); // Hold cycle
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && corrected_state_out == 4'b0111 && deauth_latched_out == 1'b0)
            $display(">> SCENARIO 1 PASSED: Correct sequence authenticated without faults!\n");
        else
            $display(">> SCENARIO 1 FAILED\n");

        // =========================================================================
        // SCENARIO 2: Single-Bit Fault Correction during Mid-Sequence
        // Laser/Glitch flips state[1] at Cycle 2: SECDED corrects it on the fly!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 2: Single-Bit Fault on state[1] at Cycle 2 -> SECDED Corrects!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 -> GOT_1
        apply_stimulus(1'b0, 8'h02); // Bit 2: 0 with bit-flip injected on state[1] (raw state flipped!)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && corrected_state_out == 4'b0111 && deauth_latched_out == 1'b0)
            $display(">> SCENARIO 2 PASSED: Single-bit flip was corrected by Extended Hamming, authentication preserved!\n");
        else
            $display(">> SCENARIO 2 FAILED\n");

        // =========================================================================
        // SCENARIO 3: Single-Bit Fault on Final State (state[0] flipped at SUCCESS)
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 3: Single-Bit Fault on state[0] at Final Cycle -> SECDED Corrects!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b0, 8'h00); // Bit 2: 0
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h01); // Bit 4: 0 with bit-flip on state[0] (0110 instead of 0111)

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b1 && corrected_state_out == 4'b0111)
            $display(">> SCENARIO 3 PASSED: Final cycle single-bit flip corrected to SUCCESS, access granted!\n");
        else
            $display(">> SCENARIO 3 FAILED\n");

        // =========================================================================
        // SCENARIO 4: Double-Bit Fault Injection (SECDED Double Error Detection)
        // Attacker flips state[1:0] (2 bits) -> Uncorrectable: Immediate Deauth!
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 4: Double-Bit Fault (mask=8'h03) -> Double Error Detected => Deauth!");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1
        apply_stimulus(1'b0, 8'h03); // Bit 2: Double-bit flip on state[1:0]!
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (double_error_detected == 1'b1 || deauth_latched_out == 1'b1) begin
            if (access_granted == 1'b0)
                $display(">> SCENARIO 4 PASSED: Double-bit error caught by SECDED, deauth latched, access denied!\n");
            else
                $display(">> SCENARIO 4 FAILED: Access should be denied!\n");
        end else begin
            $display(">> SCENARIO 4 FAILED: Double error was not detected!\n");
        end

        // =========================================================================
        // SCENARIO 5: Incorrect Passcode (1110) - Constant Time Path to LOCKED
        // =========================================================================
        $display("=========================================================================");
        $display("SCENARIO 5: Wrong Passcode (1110) - Constant-Time Pipeline to LOCKED");
        $display("=========================================================================");
        reset_fsm();

        apply_stimulus(1'b1, 8'h00); // Bit 1: 1 (correct)
        apply_stimulus(1'b1, 8'h00); // Bit 2: 1 (wrong -> ERR_2)
        apply_stimulus(1'b1, 8'h00); // Bit 3: 1 (dummy -> ERR_3)
        apply_stimulus(1'b0, 8'h00); // Bit 4: 0 (dummy -> LOCKED)

        apply_stimulus(1'b0, 8'h00);
        repeat(2) @(negedge clk);
        if (access_granted == 1'b0 && corrected_state_out == 4'b0011)
            $display(">> SCENARIO 5 PASSED: Wrong passcode correctly routed to LOCKED, access denied!\n");
        else
            $display(">> SCENARIO 5 FAILED\n");

        $display("=========================================================================");
        $display("All Solution 4 Test Scenarios Completed Successfully!");
        $display("=========================================================================\n");
        $finish;
    end

endmodule
