#pragma once

#include <stdbool.h>

#define POST_LIMIT 131072

char** parse_command(const char *cmdline);
char* postdecode(char **fields, int n_fields);
char* postdecode_fields(char *postbuf, ssize_t len, char **fields, int n_fields);
char* canonicalize_path(const char *path, size_t len);
bool urldecode(char *buf);
char* datadup(const void *in, size_t len);
