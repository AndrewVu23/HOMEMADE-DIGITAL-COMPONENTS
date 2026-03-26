module radix4mul_wf;
  initial begin
    if ($test$plusargs("WAVES")) begin
      $dumpfile("build/waveforms.vcd");
      $dumpvars(0, radix4mul);
    end
  end
endmodule
