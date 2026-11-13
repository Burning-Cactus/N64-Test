package build

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

main :: proc() {
	build_paths, err := os.glob("build/*")
	if err == nil {
		for file in build_paths {
			run_command({"rm", file})
		}
	}
	// Clean out the build directory
	build_dirs := [?]string {
		"build/ir/",
		"build/obj/",
	}
	for dir in build_dirs {
		run_command({"mkdir", "-p", dir})
	}

	ok := run_command({"odin", "build", "src",
		"-build-mode:llvm-ir",
		"-out:build/ir",
		"-target:freestanding_arm32",
		"-bedrock",
		"-no-thread-local",
		"-no-entry-point"})

	if ok {
		Obj_Desc :: struct {
			source: string,
			target: string,
		}

		objs := [?]Obj_Desc {
			// {"src/entrypoint.S", "entrypoint.o"},
			{"build/ir/*.ll", "game.o"},
		}

		for i in 0..<len(objs) {
			info := objs[i]
			source_paths, err := os.glob(info.source)
			if err != nil {
				ok = false
				continue
			}
			for source, j in source_paths {
				target_full_name := filepath.base(source)
				target_name, _ := os.split_filename(target_full_name)
				current_name := strings.concatenate({target_name, ".o"})
				target_path, _ := filepath.join({"build/obj", current_name})
				success := run_command({
						// Thanks Ryan Fleury!
						"clang", "-c", source, "-o", target_path,
						"--target=mips-unknown-elf",
						"-mcpu=mips3",
						"-mabi=32",
						"-EB",
						"-mno-abicalls",
						"-fno-pic",
						"-ffreestanding",
						"-nostdlib",
						"-fno-builtin",
						"-G", "0",
						"-Woverride-module"
				})
				if !success do ok = false
			}
		}
		fmt.printf("hi")
	}


	// n64tool and linker script both sourced from libdragon.
	if ok {
		obj_paths, err := os.glob("build/obj/*.o")
		if err != nil {
			ok = false
		}
		else {
			args := make([dynamic]string, 0, 6 + len(obj_paths))
			append(&args, "ld.lld")
			append(&args, ..obj_paths)
			append(&args, "-o", "build/obj/game.elf", "-T", "n64.ld", "-v")
			ok = run_command(args[:])
		}

	}
	if ok {
		ok = run_command({"n64tool", "-t", "\"test\"", "-o", "build/test.z64", "--align", "256", "build/obj/game.elf"})
	}
	if ok {
		ok = run_command({"sudo", "sc64deployer", "upload", "build/test.z64"})
	}
}

run_command :: proc(args: []string) -> bool {
	state, stdout, stderr, err := os.process_exec({
		command = args,
	}, context.temp_allocator)

	if len(stderr) > 0 {
		fmt.eprintf("%s\n", stderr)
	}
	if len(stdout) > 0 {
		fmt.printf("%s\n", stdout)
	}
	return state.success && err == nil
}
