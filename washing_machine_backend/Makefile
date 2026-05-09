.PHONY: analyze run wave clean

GHDL=ghdl
GHDLFLAGS=--std=08

SRC=src/washer_fsm.vhd
TB=tb/tb_washer_fsm.vhd

analyze:
	$(GHDL) -a $(GHDLFLAGS) $(SRC)
	$(GHDL) -a $(GHDLFLAGS) $(TB)

run:
	$(GHDL) -e $(GHDLFLAGS) tb_washer_fsm
	$(GHDL) -r $(GHDLFLAGS) tb_washer_fsm --stop-time=5us --fst=wave/wave.fst

wave:
	gtkwave wave/wave.fst

clean:
	rm -f *.o *.cf
	rm -f wave/*.vcd wave/*.fst