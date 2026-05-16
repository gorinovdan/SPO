.PHONY: build asm remote-demo remote-unsupported remote-interactive remote-tasks local-demo local-unsupported probe-timer clean

build:
	cd ./ast && flex -l ./lexer.l
	cd ./ast && bison -dv ./parser.y
	gcc -g -O0 -o ./app ./main.c ./ast/ast_maker.c ./analysis/ir.c ./cfg/cfg.c \
	./codegen/linear_code.c ./ast/parser.tab.c ./ast/lex.yy.c ./ast/ast.c ./view/dgml.c ./view/cfg_dgml.c

asm:
	cp ./tests/btrfs_ftp_demo.asm ./results/btrfs_ftp_demo.asm
	cp ./tests/btrfs_unsupported.asm ./results/btrfs_unsupported.asm

remote-demo: asm
	./tools/run_remote.sh ./results/btrfs_ftp_demo.asm ./tests/btrfs_ftp_commands.remote.txt exec ./results/btrfs_ftp_demo.ptptb ./results/btrfs_ftp_demo.stdout.txt ./results/btrfs_ftp_demo.trace.txt
	python3 ./tools/check_btrfs_ftp_output.py ./results/btrfs_ftp_demo.stdout.txt

remote-unsupported: asm
	./tools/run_remote.sh ./results/btrfs_unsupported.asm ../tools/vm_input.txt exec ./results/btrfs_unsupported.ptptb ./results/btrfs_unsupported.stdout.txt ./results/btrfs_unsupported.trace.txt
	python3 ./tools/check_btrfs_unsupported.py ./results/btrfs_unsupported.stdout.txt

remote-interactive: asm
	./tools/run_remote_interactive.sh ./results/btrfs_ftp_demo.asm ./results/btrfs_ftp_demo.ptptb

remote-tasks:
	./tools/run_remote_interactive.sh --list

local-demo:
	python3 ./tools/asm.py -s ./vm/spec.json -i ./tests/btrfs_ftp_demo.asm -o ./results/btrfs_ftp_demo.local.ptptb
	python3 ./tools/vm.py -s ./vm/spec.json -i ./results/btrfs_ftp_demo.local.ptptb --max-steps 200000 < ./tests/btrfs_ftp_commands.txt > ./results/btrfs_ftp_demo.local.stdout.txt
	python3 ./tools/check_btrfs_ftp_output.py ./results/btrfs_ftp_demo.local.stdout.txt

local-unsupported:
	python3 ./tools/asm.py -s ./vm/spec.json -i ./tests/btrfs_unsupported.asm -o ./results/btrfs_unsupported.local.ptptb
	python3 ./tools/vm.py -s ./vm/spec.json -i ./results/btrfs_unsupported.local.ptptb --max-steps 20000 > ./results/btrfs_unsupported.local.stdout.txt
	python3 ./tools/check_btrfs_unsupported.py ./results/btrfs_unsupported.local.stdout.txt

probe-timer:
	./tools/run_remote.sh ./tests/timer_probe.asm ../tools/vm_input.txt exec ./results/timer_probe.ptptb ./results/timer_probe.stdout.txt ./results/timer_probe.trace.txt

clean:
	rm -f ./app ./app.exe
	rm -rf ./app.dSYM
