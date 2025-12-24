#ifndef LINEAR_CODE_H
#define LINEAR_CODE_H

#include "../cfg/cfg.h"

typedef enum LC_DataKind {
	LC_DATA_CONST,
	LC_DATA_VAR
} LC_DataKind;

typedef struct LC_DataItem {
	char* name;
	LC_DataKind kind;
	IR_ConstKind const_kind;
	char* value; /* literal value for constants, NULL for variables */
	int size;    /* byte size for variables, 0 for constants */
} LC_DataItem;

typedef struct LC_Instruction {
	char* mnemonic;
	char** operands;
	int operand_count;
} LC_Instruction;

typedef struct LC_CodeBlock {
	char* name;
	LC_Instruction* instructions;
	int instruction_count;
	int instruction_capacity;
} LC_CodeBlock;

typedef struct LC_Program {
	LC_DataItem* constants;
	int constant_count;
	int constant_capacity;

	LC_DataItem* data;
	int data_count;
	int data_capacity;

	LC_CodeBlock* blocks;
	int block_count;
	int block_capacity;
} LC_Program;

LC_Program lc_generate_program(const CFG_Analysis* analysis);
void lc_free_program(LC_Program* program);
int lc_write_assembly(const LC_Program* program, const char* filename);

#endif /* LINEAR_CODE_H */
