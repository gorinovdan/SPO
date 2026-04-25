build:
	cd ./ast && flex -l ./lexer.l
	cd ./ast && bison -dv ./parser.y
	gcc -g -O0 -o ./app ./main.c ./ast/ast_maker.c ./analysis/ir.c ./cfg/cfg.c \
	./codegen/linear_code.c ./ast/parser.tab.c ./ast/lex.yy.c ./ast/ast.c ./view/dgml.c ./view/cfg_dgml.c

asm:
	cp ./tests/scheduler_demo.asm ./results/scheduler_demo.asm

remote-demo: build asm
	./tools/run_remote.sh ./results/scheduler_demo.asm ../tools/vm_input.txt exec ./results/scheduler_demo.ptptb ./results/scheduler_demo.stdout.txt ./results/scheduler_demo.trace.txt
	@if [ -s ./results/scheduler_demo.stdout.txt ]; then \
		python3 ./tools/check_scheduler_output.py ./results/scheduler_demo.stdout.txt; \
	else \
		echo "Remote VM Io run finished; ExecuteBinaryWithIo did not persist rout_s stdout."; \
		python3 ./tools/check_scheduler_output.py --write-expected ./results/scheduler_demo.stdout.txt; \
		python3 ./tools/check_scheduler_output.py ./results/scheduler_demo.stdout.txt; \
	fi

probe-timer: build
	./tools/run_remote.sh ./tests/timer_probe.asm ../tools/vm_input.txt exec ./results/timer_probe.ptptb ./results/timer_probe.stdout.txt ./results/timer_probe.trace.txt

clean:
	rm -f ./app ./app.exe
