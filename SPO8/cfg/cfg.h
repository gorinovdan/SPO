#ifndef CFG_H
#define CFG_H

#include "../analysis/ir.h"

typedef struct CFG_Error {
	char* filename;
	int line;
	int column;
	char* message;
} CFG_Error;

typedef struct CFG_Block {
	int id;

	int next;
	int true_next;
	int false_next;

	char* label;
	IRNode* ir;
	int is_circle;
	int is_break;
} CFG_Block;

typedef struct CFG_Graph {
	CFG_Block* blocks;
	int block_count;
	int block_capacity;

	int entry_id;
	int exit_id;
} CFG_Graph;

typedef struct CFG_Param {
	char* name;
	char* type;
	int size;
} CFG_Param;

typedef struct CFG_Symbol {
	char* name;
	char* type;
	int is_param;
	int is_auto_object;
} CFG_Symbol;

typedef struct CFG_Field {
	char* name;
	char* type;
	char* owner_type;
	int slot_index;
} CFG_Field;

typedef struct CFG_Method {
	char* name;
	char* mangled_name;
	char* owner_type;
	char* return_type;
	CFG_Param* params;
	int param_count;
	int is_override;
	int is_abstract;
} CFG_Method;

typedef struct CFG_UserType {
	char* name;
	int is_interface;
	char* base_name;
	char** interface_names;
	int interface_count;

	CFG_Field* fields;
	int field_count;
	int field_capacity;

	CFG_Method* methods;
	int method_count;
	int method_capacity;

	int type_id;
	int object_word_size;
} CFG_UserType;

typedef struct CFG_DispatchCase {
	char* runtime_type;
	char* impl_name;
	int type_id;
} CFG_DispatchCase;

typedef struct CFG_DispatchEntry {
	char* name;
	char* owner_type;
	char* method_name;
	char* return_type;
	CFG_Param* params;
	int param_count;
	CFG_DispatchCase* cases;
	int case_count;
	int case_capacity;
} CFG_DispatchEntry;

typedef struct CFG_Subprogram {
	char* name;
	char* signature;
	char* source_filename;
	char* owner_type;
	char* method_name;
	char* return_type;
	int is_method;
	int is_override;

	CFG_Param* params;
	int param_count;

	CFG_Symbol* symbols;
	int symbol_count;
	int symbol_capacity;

	CFG_Graph cfg;
} CFG_Subprogram;

typedef struct CFG_Analysis {
	CFG_Subprogram* subprograms;
	int subprogram_count;
	int subprogram_capacity;

	CFG_UserType* types;
	int type_count;
	int type_capacity;

	CFG_DispatchEntry* dispatchers;
	int dispatcher_count;
	int dispatcher_capacity;

	CFG_Error* errors;
	int error_count;
	int error_capacity;
} CFG_Analysis;

typedef struct CFG_InputFile {
	const char* filename;
	AST_Node* parse_tree;
} CFG_InputFile;

typedef struct CallGraph_Edge {
	int from;
	int to;
} CallGraph_Edge;

typedef struct CallGraph {
	char** node_names;
	int node_count;
	int node_capacity;

	CallGraph_Edge* edges;
	int edge_count;
	int edge_capacity;
} CallGraph;

CFG_Analysis cfg_analyze_files(const CFG_InputFile* files, int file_count);
void cfg_free_analysis(CFG_Analysis* analysis);

CallGraph cfg_build_call_graph(const CFG_Analysis* analysis);
void cfg_free_call_graph(CallGraph* graph);

#endif /* CFG_H */
