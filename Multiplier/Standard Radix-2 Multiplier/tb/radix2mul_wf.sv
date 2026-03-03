module radix2mul_wf;
  initial begin
    if ($test$plusargs("WAVES")) begin
      $dumpfile("build/waveforms.vcd");
      $dumpvars(0, radix2mul);
    end
  end
endmodule
