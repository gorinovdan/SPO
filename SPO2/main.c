#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "ast/ast_maker.h"
#include "cfg/cfg.h"
#include "view/dgml.h"
#include "view/cfg_dgml.h"

#ifdef _WIN32
#define PATH_SEP '\\'
#else
#define PATH_SEP '/'
#endif

char* filename_from_path(const char* path) {
	// 1. найти последний '/' или '\\' — разделитель пути
	const char* lastslash = strrchr(path, '/');
#ifdef _WIN32
	const char* lastbackslash = strrchr(path, '\\');
	if (lastbackslash && (!lastslash || lastbackslash > lastslash)) {
		lastslash = lastbackslash;
	}
#endif
	// 2. извлечь папку и имя файла
	if (lastslash) {
		int filename_len = strlen(lastslash + 1) + 1;
		char* filename = malloc(filename_len);
		strncpy(filename, lastslash + 1, filename_len);
		return filename;
	}
	else {
		int filename_len = strlen(path) + 1;
		char* filename = malloc(filename_len);
		strncpy(filename, path, filename_len);
		return filename;
	}
}

char* dirname_from_path(const char* path) {
	const char* lastslash = strrchr(path, '/');
#ifdef _WIN32
	const char* lastbackslash = strrchr(path, '\\');
	if (lastbackslash && (!lastslash || lastbackslash > lastslash)) {
		lastslash = lastbackslash;
	}
#endif
	if (!lastslash) {
		char* dir = malloc(2);
		strcpy(dir, ".");
		return dir;
	}
	size_t len = (size_t)(lastslash - path);
	if (len == 0) len = 1; /* root */
	char* dir = malloc(len + 1);
	strncpy(dir, path, len);
	dir[len] = '\0';
	return dir;
}

static int is_directory_path(const char* path) {
	struct stat st;
	if (stat(path, &st) != 0) return 0;
#ifdef _WIN32
	return (st.st_mode & _S_IFDIR) != 0;
#else
	return S_ISDIR(st.st_mode);
#endif
}

static void print_usage(const char* prog) {
	fprintf(stderr, "Usage: %s [-o output_dir] <input_files...>\n", prog);
	fprintf(stderr, "  If output_dir is omitted, results are written next to each input file.\n");
}

int main(int argc, char* argv[]) {
	if (argc < 2) {
		print_usage(argv[0]);
		return 1;
	}

	const char* output_dir = NULL;
	const char** input_files = malloc((argc - 1) * sizeof(char*));
	int input_files_count = 0;

	for (int i = 1; i < argc; i++) {
		if ((strcmp(argv[i], "-o") == 0 || strcmp(argv[i], "--out") == 0)) {
			if (i + 1 >= argc) {
				fprintf(stderr, "Missing value for %s\n", argv[i]);
				free(input_files);
				return 1;
			}
			output_dir = argv[i + 1];
			i++;
			continue;
		}
		input_files[input_files_count++] = argv[i];
	}

	/* Backward-compatible: `app <inputs...> <output_dir>` */
	if (!output_dir && input_files_count >= 2 && is_directory_path(input_files[input_files_count - 1])) {
		output_dir = input_files[input_files_count - 1];
		input_files_count--;
	}

	if (input_files_count < 1) {
		print_usage(argv[0]);
		free(input_files);
		return 1;
	}

	AST_Wrap** asts = malloc(input_files_count * sizeof(AST_Wrap*));
	CFG_InputFile* cfg_files = malloc(input_files_count * sizeof(CFG_InputFile));
	int parsed_files_count = 0;

	for (int i = 0; i < input_files_count; i++) {
		AST_Wrap* wrap = create_ast_wrap(input_files[i]);
		if (!wrap) {
			fprintf(stderr, "Failed to parse file: %s\n", input_files[i]);
			continue;
		}

		/* AST export (as in SPO2Denis reference) */
		char* ast_source_name = filename_from_path(wrap->filename);
		char* ast_out_dir = output_dir ? strdup(output_dir) : dirname_from_path(wrap->filename);
		int ast_out_sz = snprintf(NULL, 0, "%s%cast.%s.dgml", ast_out_dir, PATH_SEP, ast_source_name) + 1;
		char* ast_out_path = malloc(ast_out_sz);
		snprintf(ast_out_path, ast_out_sz, "%s%cast.%s.dgml", ast_out_dir, PATH_SEP, ast_source_name);
		export_ast_dgml(wrap->ast, ast_out_path);
		free(ast_out_path);
		free(ast_out_dir);
		free(ast_source_name);

		asts[parsed_files_count] = wrap;
		cfg_files[parsed_files_count].filename = wrap->filename;
		cfg_files[parsed_files_count].parse_tree = wrap->ast;
		parsed_files_count++;
	}

	if (parsed_files_count == 0) {
		fprintf(stderr, "No input files were parsed successfully.\n");
		free(cfg_files);
		free(asts);
		free(input_files);
		return 1;
	}

	CFG_Analysis analysis = cfg_analyze_files(cfg_files, parsed_files_count);

	for (int i = 0; i < analysis.error_count; i++) {
		const CFG_Error* e = &analysis.errors[i];
		fprintf(stderr, "%s:%d:%d: %s\n", e->filename ? e->filename : "<input>", e->line, e->column, e->message ? e->message : "");
	}

	for (int i = 0; i < analysis.subprogram_count; i++) {
		const CFG_Subprogram* sp = &analysis.subprograms[i];

		char* source_name = filename_from_path(sp->source_filename ? sp->source_filename : "");
		char* func_out_dir = output_dir ? strdup(output_dir) : dirname_from_path(sp->source_filename ? sp->source_filename : "");

		int out_sz = snprintf(NULL, 0, "%s%c%s.%s.dgml", func_out_dir, PATH_SEP, source_name, sp->name) + 1;
		char* out_path = malloc(out_sz);
		snprintf(out_path, out_sz, "%s%c%s.%s.dgml", func_out_dir, PATH_SEP, source_name, sp->name);

		export_cfg_dgml(sp, out_path);

		free(out_path);
		free(func_out_dir);
		free(source_name);
	}

	CallGraph cg = cfg_build_call_graph(&analysis);

	const CFG_Subprogram* main_sp = NULL;
	for (int i = 0; i < analysis.subprogram_count; i++) {
		if (analysis.subprograms[i].name && strcmp(analysis.subprograms[i].name, "main") == 0) {
			main_sp = &analysis.subprograms[i];
			break;
		}
	}

	char* cg_out_dir = NULL;
	if (output_dir) {
		cg_out_dir = strdup(output_dir);
	}
	else if (main_sp && main_sp->source_filename) {
		cg_out_dir = dirname_from_path(main_sp->source_filename);
	}
	else {
		cg_out_dir = dirname_from_path(cfg_files[0].filename);
	}

	int callgraph_sz = snprintf(NULL, 0, "%s%cfun.calls.graph.dgml", cg_out_dir, PATH_SEP) + 1;
	char* callgraph_path = malloc(callgraph_sz);
	snprintf(callgraph_path, callgraph_sz, "%s%cfun.calls.graph.dgml", cg_out_dir, PATH_SEP);
	export_callgraph_dgml(&cg, callgraph_path);
	free(callgraph_path);

	int cfg_overview_sz = snprintf(NULL, 0, "%s%ccfg.dgml", cg_out_dir, PATH_SEP) + 1;
	char* cfg_overview_path = malloc(cfg_overview_sz);
	snprintf(cfg_overview_path, cfg_overview_sz, "%s%ccfg.dgml", cg_out_dir, PATH_SEP);
	export_cfg_overview_dgml(&analysis, cfg_overview_path);
	free(cfg_overview_path);

	free(cg_out_dir);
	cfg_free_call_graph(&cg);

	cfg_free_analysis(&analysis);

	for (int i = 0; i < parsed_files_count; i++) {
		free_ast_wrap(asts[i]);
	}
	free(cfg_files);
	free(asts);
	free(input_files);

	return 0;
}
