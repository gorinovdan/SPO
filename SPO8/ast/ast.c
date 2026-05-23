#include <stdio.h>
#include <inttypes.h>
#include <string.h>
#include <stdlib.h>
#include "ast.h"


AST_Node* create_arg_def_node(AST_Node* id, AST_Node* type_ref) {
	AST_Node* node = malloc(sizeof(AST_Node));
	node->type = AST_ARG_DEF;
	node->loc = (AST_Loc){ 0 };
	if (type_ref == NULL) {
		node->compound.child_count = 1;
		node->compound.children = malloc(sizeof(AST_Node*));
		node->compound.children[0] = id;
	}
	else {
		node->compound.child_count = 2;
		node->compound.children = malloc(2 * sizeof(AST_Node*));
		node->compound.children[0] = id;
		node->compound.children[1] = type_ref;
	}
	return node;
}

AST_Node* create_type_ref_node(AST_Node* type) {
	AST_Node* node = malloc(sizeof(AST_Node));
	node->type = AST_TYPE_REF;
	node->loc = (AST_Loc){ 0 };
	node->compound.child_count = 1;
	node->compound.children = malloc(sizeof(AST_Node*));
	node->compound.children[0] = type;
	return node;
}

//AST_Node* create_array_node(AST_Node* type, int dimention) {
//	AST_Node* node = malloc(sizeof(AST_Node));
//	node->type = AST_TYPE_ARRAY;
//	node->compound.child_count = 2;
//	node->compound.children = malloc(2 * sizeof(AST_Node*));
//	node->compound.children[0] = type;
//	AST_Node* dimention_node = malloc(sizeof(AST_Node));
//	dimention_node->type = AST_TYPE_ARRAY_DIMENTION;
//	dimention_node->arr_dimention = dimention;
//	node->compound.children[1] = dimention_node;
//	return node;
//}

AST_Node* create_id_node(char* id) {
	AST_Node* node = malloc(sizeof(AST_Node));
	node->type = AST_ID;
	node->loc = (AST_Loc){ 0 };
	node->id = malloc(strlen(id) + 1);
	snprintf(node->id, strlen(id) + 1, "%s", id);
	free(id);
	return node;
}

AST_Node* create_string_node(char* string_val) {
	AST_Node* node = malloc(sizeof(AST_Node));
	node->type = AST_STRING;
	node->loc = (AST_Loc){ 0 };
	node->string_value = malloc(strlen(string_val) + 1);
	snprintf(node->string_value, strlen(string_val) + 1, "%s", string_val);
	free(string_val);
	return node;
}

AST_Node* create_char_node(char char_value) {
	AST_Node* node = malloc(sizeof(AST_Node));
	node->type = AST_CHAR;
	node->loc = (AST_Loc){ 0 };
	node->char_value = char_value;
	return node;
}


AST_Node* create_dec_node(char* num_str, NodeType type) {
	uint32_t num_val;
	switch (type) {
	case AST_BOOL: {
		if (strcmp(num_str, "true") == 0) {
			num_val = 1;
		}
		else {
			num_val = 0;
		}
		break;
	}
	case AST_HEX: {
		num_val = strtoul(num_str, NULL, 16);
		break;
	}
	case AST_BIT: {
		num_val = strtoul(num_str + 2, NULL, 2);
		break;
	}
	case AST_NUM: {
		num_val = strtoul(num_str, NULL, 10);
		break;
	}
	default: {
		num_val = 0;
		break;
	}
	}
	AST_Node* node = malloc(sizeof(AST_Node));
	node->type = type;
	node->loc = (AST_Loc){ 0 };
	node->num_val = num_val;
	int num_str_len = strlen(num_str) + 1;
	node->num_str = malloc(num_str_len);
	snprintf(node->num_str, num_str_len, "%s", num_str);

	free(num_str);
	return node;
}

AST_Node* create_type_x_node(char* type_name, NodeType type) {
	AST_Node* node = malloc(sizeof(AST_Node));
	node->type = type;
	node->loc = (AST_Loc){ 0 };
	node->type_name = malloc(strlen(type_name) + 1);
	snprintf(node->type_name, strlen(type_name) + 1, "%s", type_name);
	free(type_name);
	return node;
}



AST_Node* create_node(NodeType type) {
	AST_Node* node = calloc(1, sizeof(AST_Node));
	node->type = type;
	return node;
}

AST_Node* create_list_node(AST_Node* first) {
	AST_Node* node = malloc(sizeof(AST_Node));
	node->type = AST_LIST;
	node->loc = (AST_Loc){ 0 };
	node->compound.child_count = 1;
	node->compound.children = malloc(sizeof(AST_Node*));
	node->compound.children[0] = first;
	return node;
}

AST_Node* append_to_list_node(AST_Node* list, AST_Node* child) {
	int old_count = list->compound.child_count;
	list->compound.child_count += 1;
	list->compound.children = realloc(list->compound.children, list->compound.child_count * sizeof(AST_Node*));
	list->compound.children[old_count] = child;
	return list;
}

void free_ast(AST_Node* node) {
	if (!node) return;
	switch (node->type) {
	case AST_CHAR:
	case AST_TYPE_ARRAY_DIMENTION:
		// Статически заданное значение, освобождать нечего.
		break;
	case AST_HEX:
	case AST_BIT:
	case AST_BOOL:
	case AST_NUM:
		free(node->num_str);
		break;
	case AST_TYPE_STRING:
	case AST_TYPE_BOOL:
	case AST_TYPE_INT:
	case AST_TYPE_UINT:
	case AST_TYPE_LONG:
	case AST_TYPE_ULONG:
	case AST_TYPE_BYTE:
	case AST_TYPE_CHAR:
		free(node->type_name);
		break;
	case AST_ID:
		free(node->id);
		break;
	case AST_STRING:
		free(node->string_value);
		break;
	default:
		for (int i = 0; i < node->compound.child_count; i++) {
			free_ast(node->compound.children[i]);
		}
		free(node->compound.children);
		break;
	}
	free(node);
}

static char* join_list(char** expr_list, int list_sz) {
	int total_len = 0;
	for (int i = 0; i < list_sz; i++) {
		total_len += strlen(expr_list[i]);
	}
	total_len += (list_sz - 1) * strlen(", ");
	total_len += 1;

	char* result = malloc(total_len);
	if (!result) return NULL;

	result[0] = '\0';
	for (int i = 0; i < list_sz; i++) {
		strcat(result, expr_list[i]);
		if (i < list_sz - 1) {
			strcat(result, ", ");
		}
	}
	return result;
}

static char* specify_op(AST_Node* node, char* op) {
	int res_len;
	char* result;
	char* child1 = expr_to_string(node->compound.children[0]);
	char* child2 = expr_to_string(node->compound.children[1]);
	res_len = snprintf(NULL, 0, "(%s %s %s)", child1, op, child2) + 1;
	result = malloc(res_len);
	snprintf(result, res_len, "(%s %s %s)", child1, op, child2);
	free(child1);
	free(child2);
	return result;
}

// Возвращает NUL-терминированную строку.
char* expr_to_string(AST_Node* node) {
	char* result;
	int res_len;
	if (!node) {
		result = malloc(sizeof(char));
		result[0] = '\0';
		return result;
	}
	switch (node->type) {
	case AST_TYPE_STRING:
	case AST_TYPE_BOOL:
	case AST_TYPE_INT:
	case AST_TYPE_UINT:
	case AST_TYPE_LONG:
	case AST_TYPE_ULONG:
	case AST_TYPE_BYTE:
	case AST_TYPE_CHAR: {
		res_len = strlen(node->type_name) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "%s", node->type_name);
		break;
	}
	case AST_ID: {
		res_len = strlen(node->id) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "%s", node->id);
		break;
	}
	case AST_STRING: {
		res_len = snprintf(NULL, 0, "&quot;%s&quot;", node->string_value) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "&quot;%s&quot;", node->string_value);
		break;
	}
	case AST_CHAR: {
		res_len = snprintf(NULL, 0, "&apos;%c&apos;", node->char_value) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "&apos;%c&apos;", node->char_value);
		break;
	}
	case AST_BIT:
	case AST_BOOL:
	case AST_NUM:
	case AST_HEX: {
		res_len = strlen(node->num_str) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "%s", node->num_str);
		break;
	}
	case AST_UMINUS: {
		char* child = expr_to_string(node->compound.children[0]);
		res_len = snprintf(NULL, 0, "%s %s", node->op, child) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "%s %s", node->op, child);
		free(child);
		break;
	}
	case AST_L: {
		result = specify_op(node, "&lt;");
		break;
	}
	case AST_G: {
		result = specify_op(node, "&gt;");
		break;
	}
	case AST_LE: {
		result = specify_op(node, "&lt;=");
		break;
	}
	case AST_GE: {
		result = specify_op(node, "&gt;=");
		break;
	}
	case AST_AND: {
		result = specify_op(node, "&amp;&amp;");
		break;
	}
	case AST_ASSIG_EQUAL:
	case AST_MUL:
	case AST_DIV:
	case AST_ADD:
	case AST_SUB:
	case AST_REM:
	case AST_EQ:
	case AST_NE:
	case AST_OR: {
		result = specify_op(node, node->op);
		break;
	}
	case AST_TYPE_REF: {
		if (node->compound.child_count >= 1) {
			result = expr_to_string(node->compound.children[0]);
		}
		else {
			result = malloc(sizeof(char));
			result[0] = '\0';
		}
		break;
	}
	case AST_VAR_DECL: {
		char* name = expr_to_string(node->compound.children[0]);
		char* type = (node->compound.child_count >= 2) ? expr_to_string(node->compound.children[1]) : strdup("");
		if (node->compound.child_count >= 3) {
			char* init = expr_to_string(node->compound.children[2]);
			res_len = snprintf(NULL, 0, "%s of %s = %s", name, type, init) + 1;
			result = malloc(res_len);
			snprintf(result, res_len, "%s of %s = %s", name, type, init);
			free(init);
		}
		else {
			res_len = snprintf(NULL, 0, "%s of %s", name, type) + 1;
			result = malloc(res_len);
			snprintf(result, res_len, "%s of %s", name, type);
		}
		free(name);
		free(type);
		break;
	}
	case AST_FIELD_DEF: {
		char* name = expr_to_string(node->compound.children[0]);
		char* type = (node->compound.child_count >= 2) ? expr_to_string(node->compound.children[1]) : strdup("");
		res_len = snprintf(NULL, 0, "%s of %s", name, type) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "%s of %s", name, type);
		free(name);
		free(type);
		break;
	}
	case AST_TYPE_ARRAY: {
		if (node->compound.child_count >= 2) {
			char* base = expr_to_string(node->compound.children[0]);
			char* dim = expr_to_string(node->compound.children[1]);
			res_len = snprintf(NULL, 0, "%s array[%s]", base, dim) + 1;
			result = malloc(res_len);
			snprintf(result, res_len, "%s array[%s]", base, dim);
			free(base);
			free(dim);
		}
		else {
			result = malloc(sizeof(char));
			result[0] = '\0';
		}
		break;
	}
	case AST_CALL: {
		char* callee = expr_to_string(node->compound.children[0]);
		char* args = NULL;
		if (node->compound.child_count >= 2) {
			args = expr_to_string(node->compound.children[1]);
		}
		else {
			args = malloc(sizeof(char));
			args[0] = '\0';
		}

		res_len = snprintf(NULL, 0, "%s(%s)", callee, args) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "%s(%s)", callee, args);
		free(callee);
		free(args);
		break;
	}
	case AST_MEMBER_ACCESS: {
		char* base = expr_to_string(node->compound.children[0]);
		char* member = expr_to_string(node->compound.children[1]);
		res_len = snprintf(NULL, 0, "%s.%s", base, member) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "%s.%s", base, member);
		free(base);
		free(member);
		break;
	}
	case AST_RANGE: {
		char* start = expr_to_string(node->compound.children[0]);
		if (node->compound.child_count >= 2) {
			char* end = expr_to_string(node->compound.children[1]);
			res_len = snprintf(NULL, 0, "%s .. %s", start, end) + 1;
			result = malloc(res_len);
			snprintf(result, res_len, "%s .. %s", start, end);
			free(end);
		}
		else {
			res_len = snprintf(NULL, 0, "%s", start) + 1;
			result = malloc(res_len);
			snprintf(result, res_len, "%s", start);
		}
		free(start);
		break;
	}
	case AST_SLICE: {
		if (node->compound.child_count >= 2) {
			char* base = expr_to_string(node->compound.children[0]);
			char* ranges = expr_to_string(node->compound.children[1]);
			res_len = snprintf(NULL, 0, "%s[%s]", base, ranges) + 1;
			result = malloc(res_len);
			snprintf(result, res_len, "%s[%s]", base, ranges);
			free(base);
			free(ranges);
		}
		else {
			result = malloc(sizeof(char));
			result[0] = '\0';
		}
		break;
	}
	case AST_TYPE_DEF: {
		char* name = expr_to_string(node->compound.children[0]);
		res_len = snprintf(NULL, 0, "type %s", name) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "type %s", name);
		free(name);
		break;
	}
	case AST_INTERFACE_DEF: {
		char* name = expr_to_string(node->compound.children[0]);
		res_len = snprintf(NULL, 0, "interface %s", name) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "interface %s", name);
		free(name);
		break;
	}
	case AST_LIST: {
		char** expt_str_list = malloc(node->compound.child_count * sizeof(char*));
		for (int i = 0; i < node->compound.child_count; i++) {
			expt_str_list[i] = expr_to_string(node->compound.children[i]);
		}
		result = join_list(expt_str_list, node->compound.child_count);
		for (int i = 0; i < node->compound.child_count; i++) {
			free(expt_str_list[i]);
		}
		free(expt_str_list);
		break;
	}
	/*case AST_CALL_OR_INDEXER: {
		char* name = expr_to_string(node->compound.children[0]);
		char* args = expr_to_string(node->compound.children[1]);
		res_len = snprintf(NULL, 0, "%s(%s)", name, args) + 1;
		result = malloc(res_len);
		snprintf(result, res_len, "%s(%s)", name, args) + 1;
		free(name);
		free(args);
		break;
	}*/
	default: {
		result = malloc(sizeof(char));
		result[0] = '\0';
	}
	}

	return result;
}
