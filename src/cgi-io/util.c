#include <ctype.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <stdio.h>

#include "util.h"

char **
parse_command(const char *cmdline)
{
	const char *p = cmdline, *s;
	char **argv = NULL, *out;
	size_t arglen = 0;
	int argnum = 0;
	bool esc;

	while (isspace(*cmdline))
		cmdline++;

	for (p = cmdline, s = p, esc = false; p; p++) {
		if (esc) {
			esc = false;
		}
		else if (*p == '\\' && p[1] != 0) {
			esc = true;
		}
		else if (isspace(*p) || *p == 0) {
			if (p > s) {
				argnum += 1;
				arglen += sizeof(char *) + (p - s) + 1;
			}

			s = p + 1;
		}

		if (*p == 0)
			break;
	}

	if (arglen == 0)
		return NULL;

	argv = calloc(1, arglen + sizeof(char *));

	if (!argv)
		return NULL;

	out = (char *)argv + sizeof(char *) * (argnum + 1);
	argv[0] = out;

	for (p = cmdline, s = p, esc = false, argnum = 0; p; p++) {
		if (esc) {
			esc = false;
			*out++ = *p;
		}
		else if (*p == '\\' && p[1] != 0) {
			esc = true;
		}
		else if (isspace(*p) || *p == 0) {
			if (p > s) {
				*out++ = ' ';
				argv[++argnum] = out;
			}

			s = p + 1;
		}
		else {
			*out++ = *p;
		}

		if (*p == 0)
			break;
	}

	argv[argnum] = NULL;
	out[-1] = 0;

	return argv;
}

char *
postdecode_fields(char *postbuf, ssize_t len, char **fields, int n_fields)
{
	char *p;
	int i, field, found = 0;

	for (p = postbuf, i = 0; i < len; i++)
	{
		if (postbuf[i] == '=')
		{
			postbuf[i] = 0;

			for (field = 0; field < (n_fields * 2); field += 2)
			{
				if (!strcmp(p, fields[field]))
				{
					fields[field + 1] = postbuf + i + 1;
					found++;
				}
			}
		}
		else if (postbuf[i] == '&' || postbuf[i] == '\0')
		{
			postbuf[i] = 0;

			if (found >= n_fields)
				break;

			p = postbuf + i + 1;
		}
	}

	for (field = 0; field < (n_fields * 2); field += 2)
	{
		if (!urldecode(fields[field + 1]))
		{
			free(postbuf);
			return NULL;
		}
	}

	return postbuf;
}

char *
postdecode(char **fields, int n_fields)
{
	const char *var;
	char *p, *postbuf;
	ssize_t len = 0, rlen = 0, content_length = 0;

	var = getenv("CONTENT_TYPE");

	if (!var || strncmp(var, "application/x-www-form-urlencoded", 33))
		return NULL;

	var = getenv("CONTENT_LENGTH");

	if (!var)
		return NULL;

	content_length = strtol(var, &p, 10);

	if (p == var || content_length <= 0 || content_length >= POST_LIMIT)
		return NULL;

	postbuf = calloc(1, content_length + 1);

	if (postbuf == NULL)
		return NULL;

	for (len = 0; len < content_length; )
	{
		rlen = read(0, postbuf + len, content_length - len);

		if (rlen <= 0)
			break;

		len += rlen;
	}

	if (len < content_length)
	{
		free(postbuf);
		return NULL;
	}

	return postdecode_fields(postbuf, len, fields, n_fields);
}

char *
datadup(const void *in, size_t len)
{
	char *out = malloc(len + 1);

	if (!out)
		return NULL;

	memcpy(out, in, len);

	*(out + len) = 0;

	return out;
}

char *
canonicalize_path(const char *path, size_t len)
{
	char *canonpath, *cp;
	const char *p, *e;

	if (path == NULL || *path == '\0')
		return NULL;

	canonpath = datadup(path, len);

	if (canonpath == NULL)
		return NULL;

	/* normalize */
	for (cp = canonpath, p = path, e = path + len; p < e; ) {
		if (*p != '/')
			goto next;

		/* skip repeating / */
		if ((p + 1 < e) && (p[1] == '/')) {
			p++;
			continue;
		}

		/* /./ or /../ */
		if ((p + 1 < e) && (p[1] == '.')) {
			/* skip /./ */
			if ((p + 2 >= e) || (p[2] == '/')) {
				p += 2;
				continue;
			}

			/* collapse /x/../ */
			if ((p + 2 < e) && (p[2] == '.') && ((p + 3 >= e) || (p[3] == '/'))) {
				while ((cp > canonpath) && (*--cp != '/'))
					;

				p += 3;
				continue;
			}
		}

next:
		*cp++ = *p++;
	}

	/* remove trailing slash if not root / */
	if ((cp > canonpath + 1) && (cp[-1] == '/'))
		cp--;
	else if (cp == canonpath)
		*cp++ = '/';

	*cp = '\0';

	return canonpath;
}

bool
urldecode(char *buf)
{
	char *c, *p;

	if (!buf || !*buf)
		return true;

#define hex(x) \
	(((x) <= '9') ? ((x) - '0') : \
		(((x) <= 'F') ? ((x) - 'A' + 10) : \
			((x) - 'a' + 10)))

	for (c = p = buf; *p; c++)
	{
		if (*p == '%')
		{
			if (!isxdigit(*(p + 1)) || !isxdigit(*(p + 2)))
				return false;

			*c = (char)(16 * hex(*(p + 1)) + hex(*(p + 2)));

			p += 3;
		}
		else if (*p == '+')
		{
			*c = ' ';
			p++;
		}
		else
		{
			*c = *p++;
		}
	}

	*c = 0;

	return true;
}
