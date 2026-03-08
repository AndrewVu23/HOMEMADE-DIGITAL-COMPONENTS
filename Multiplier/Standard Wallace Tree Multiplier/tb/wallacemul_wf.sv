module wallacemul_wf;
  initial begin
    if ($test$plusargs("WAVES")) begin
      $dumpfile("build/waveforms.vcd");
      $dumpvars(0, wallacemul);
    end
  end
endmodule
