title=Erbium Minion Isotope TRM
client=Public Release
docstatus=Tapeout Release Candidate
os_docstatus=Tapeout Release Candidate
document-sha=$(shell git rev-parse --short HEAD )+post1
authoremail=jvs@nekko.ai
variables=-V title:"$(title)" -V client:"$(client)" -Vauthoremail:$(authoremail) -V document-sha:$(document-sha) -V status:"$(docstatus)"
os_variables=-V title:"$(title)" -V client:"$(client)" -Vauthoremail:$(authoremail) -V document-sha:$(document-sha) -V status:"$(os_docstatus)"
os_files=index.md signals.md bringup.md prcm.md interrupts.md interconnect.md
ip_files=../ip/xspi/doc/xspi.md sfpd.md sccr.md cpu_subsystem.md minion.md gpio.md i2c.md mram.md qspi.md uart.md 
verif_files=verification.md simulation.md dv_master_plan.md
BrokenFiles=clint.md 
files=$(os_files) $(ip_files) $(verif_files) xspi_mm.md cpu_mm.md  packaging.md CHANGELOG.md 
drawing=Erbium_RISCV_Isotope.drawio
IS_MOUNTED := $(shell [ -f $(drawing) ] && echo "yes" || echo "no")

all: reference_manual.pdf
os_reference_manual.pdf:.genpng *.md .regspec Makefile
	pandoc --toc --from=markdown+lists_without_preceding_blankline  -F pandoc-imagine $(os_variables) -o os_reference_manual.pdf -s --template=$(HOME)/.pandoc/template/dyu/aifoundry.template $(os_files) 
reference_manual.pdf:reference_manual.tex
	latexmk -C $<
	pdflatex $<
	pdflatex $<
	pdflatex $<
reference_manual.tex: .genpng *.md .regspec Makefile
	#drawio -x -f png -o out -p0 drawing.drawio

	#pandoc --toc --from=markdown+lists_without_preceding_blankline  -F pandoc-imagine $(variables) -o reference_manual.pdf -s --template=$(HOME)/.pandoc/template/dyu/veevx.template $(files) 
	pandoc --toc --from=markdown+lists_without_preceding_blankline  -F pandoc-imagine $(variables) -o reference_manual.tex -s --template=$(HOME)/.pandoc/template/dyu/ainekko.template $(files) 
	#cd output && pdflatex reference_manual.tex && pdflatex reference_manual.tex && pdflatex reference_manual.tex
	#pandoc --toc --from=markdown+lists_without_preceding_blankline  -F pandoc-imagine $(variables) -o output/reference_manual1.tex -s $(files) 
ifeq ($(IS_MOUNTED),yes)
.genpng:$(drawing)
	drawio -x -f png -o output/dut.png -p0  $(drawing)
	drawio -x -f png -o output/arch.png -p1  $(drawing)
	# drawio -x -f png -o output/clk.png -p2  $(drawing)
	drawio -x -f png -o output/powerAware.png -p3  $(drawing)
	drawio -x -f png -o output/clkDiv.png -p4  $(drawing)
	drawio -x -f png -o output/clk_domains.png -p5  $(drawing)
	drawio -x -f png -o output/resetSequence.png -p6  $(drawing)
	drawio -x -f png -o output/shireIntegration.png -p7  $(drawing)
	drawio -x -f png -o output/verification.png -p8  $(drawing)
	drawio -x -f png -o output/matrix.png -p9  $(drawing)
	drawio -x -f png -o output/gpio.png -p11  $(drawing)
	drawio -x -f png -o output/interrupts.png -p12  $(drawing)
	drawio -x -f png -o output/bootSequence.png -p14  $(drawing)
	drawio -x -f png -o output/thermalSensor.png -p17  $(drawing)
	drawio -x -f png -o output/packaging.png -p18  $(drawing)
	touch .genpng
else
.genpng:
	@echo "Warning: gdrive not mounted. Using stale/local diagrams ."
endif
clean:
	rm .genpng .regspec reference_manual.* os_reference_manual.* output/* || echo 1
release :clean os_reference_manual.pdf
	cp  output/*.png /prj/hdl/aifoundry/erbium/docs/silicon/output
	cp $(os_files) /prj/hdl/aifoundry/erbium/docs/silicon/

.regspec: ../regblocks/systemrdl/periph.rdl ../regblocks/systemrdl/system.rdl ../regblocks/systemrdl/mram.rdl  ../regblocks/systemrdl/top.rdl
	make -C ../regblocks/systemrdl
	perl -pi -e 's/## Erbium_CPU address map/# Erbium_CPU address map/' registers.md
	touch .regspec
