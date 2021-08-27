/*
 * cgi-io - LuCI non-RPC helper
 *
 *   Copyright (C) 2013 Jo-Philipp Wich <jo@mein.io>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#define _GNU_SOURCE /* splice(), SPLICE_F_MORE */

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <ctype.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/sendfile.h>
#include <sys/ioctl.h>
#include <linux/fs.h>
#include <libubox/uloop.h>
#include <libubox/blobmsg.h>
#include <json-c/json.h>
#include <time.h>
#include <linux/kernel.h>
#include <sys/sysinfo.h>

#include "util.h"
#include "multipart_parser.h"

#ifndef O_TMPFILE
#define O_TMPFILE	(020000000 | O_DIRECTORY)
#endif

#define READ_BLOCK 4096

enum part {
	PART_UNKNOWN,
	PART_SESSIONID,
	PART_FILENAME,
	PART_FILEMODE,
	PART_FILEDATA
};

const char *parts[] = {
	"(bug)",
	"sessionid",
	"filename",
	"filemode",
	"filedata",
};

struct state
{
	bool is_content_disposition;
	enum part parttype;
	char *sessionid;
	char *filename;
	bool filedata;
	int filemode;
	int filefd;
	int tempfd;
};

static struct state st;

enum {
	SES_ACCESS,
	__SES_MAX,
};

//static const struct blobmsg_policy ses_policy[__SES_MAX] = {
//	[SES_ACCESS] = { .name = "access", .type = BLOBMSG_TYPE_BOOL },
//};

static long get_uptime()
{
	struct sysinfo s_info;
	int error = sysinfo(&s_info);
	if(error != 0) return -1;
	return s_info.uptime;
}

static bool
session_access(const char *sid, const char *scope, const char *obj, const char *func)
{
	if (sid) {
		char p[255];
		long atime;
		struct json_object * json_policy_array;
		long t = get_uptime();
		
		if (t < 0) return false;
		strcpy(p, "/tmp/luci-sessions/");
		strcat(p, sid);
		json_policy_array = json_object_from_file(p);
		atime = (long) json_object_get_int64(json_object_object_get(json_policy_array, "atime"));

		if(atime + 15 * 60 > t){
			return true;
		}
	}
	return false;
}

static char *
checksum(const char *applet, size_t sumlen, const char *file)
{
	pid_t pid;
	int r;
	int fds[2];
	static char chksum[65];

	if (pipe(fds))
		return NULL;

	switch ((pid = fork()))
	{
	case -1:
		return NULL;

	case 0:
		uloop_done();

		dup2(fds[1], 1);

		close(0);
		close(2);
		close(fds[0]);
		close(fds[1]);

		if (execl("/bin/busybox", "/bin/busybox", applet, file, NULL))
			return NULL;

		break;

	default:
		memset(chksum, 0, sizeof(chksum));
		r = read(fds[0], chksum, sumlen);

		waitpid(pid, NULL, 0);
		close(fds[0]);
		close(fds[1]);

		if (r < 0)
			return NULL;
	}

	return chksum;
}

static int
response(bool success, const char *message)
{
	char *chksum;
	struct stat s;

	printf("Status: 200 OK\r\n");
	printf("Content-Type: text/plain\r\n\r\n{\n");

	if (success)
	{
		if (!stat(st.filename, &s))
			printf("\t\"size\": %u,\n", (unsigned int)s.st_size);
		else
			printf("\t\"size\": null,\n");

		chksum = checksum("md5sum", 32, st.filename);
		printf("\t\"checksum\": %s%s%s,\n",
			chksum ? "\"" : "",
			chksum ? chksum : "null",
			chksum ? "\"" : "");

		chksum = checksum("sha256sum", 64, st.filename);
		printf("\t\"sha256sum\": %s%s%s\n",
			chksum ? "\"" : "",
			chksum ? chksum : "null",
			chksum ? "\"" : "");
	}
	else
	{
		if (message)
			printf("\t\"message\": \"%s\",\n", message);

		printf("\t\"failure\": [ %u, \"%s\" ]\n", errno, strerror(errno));

		if (st.filefd > -1 && st.filename)
			unlink(st.filename);
	}

	printf("}\n");

	return -1;
}

static int
failure(int code, int e, const char *message)
{
	printf("Status: %d %s\r\n", code, message);
	printf("Content-Type: text/plain\r\n\r\n");
	printf("%s", message);

	if (e)
		printf(": %s", strerror(e));

	printf("\n");

	return -1;
}

static int
filecopy(void)
{
	int len;
	char buf[READ_BLOCK];

	if (!st.filedata)
	{
		close(st.tempfd);
		errno = EINVAL;
		return response(false, "No file data received");
	}

	snprintf(buf, sizeof(buf), "/proc/self/fd/%d", st.tempfd);

	if (unlink(st.filename) < 0 && errno != ENOENT)
	{
		close(st.tempfd);
		return response(false, "Failed to unlink existing file");
	}

	if (linkat(AT_FDCWD, buf, AT_FDCWD, st.filename, AT_SYMLINK_FOLLOW) < 0)
	{
		if (lseek(st.tempfd, 0, SEEK_SET) < 0)
		{
			close(st.tempfd);
			return response(false, "Failed to rewind temp file");
		}

		st.filefd = open(st.filename, O_CREAT | O_TRUNC | O_WRONLY, 0600);

		if (st.filefd < 0)
		{
			close(st.tempfd);
			return response(false, "Failed to open target file");
		}

		while ((len = read(st.tempfd, buf, sizeof(buf))) > 0)
		{
			if (write(st.filefd, buf, len) != len)
			{
				close(st.tempfd);
				close(st.filefd);
				return response(false, "I/O failure while writing target file");
			}
		}

		close(st.filefd);
	}

	close(st.tempfd);

	if (chmod(st.filename, st.filemode))
		return response(false, "Failed to chmod target file");

	return 0;
}

static int
header_field(multipart_parser *p, const char *data, size_t len)
{
	st.is_content_disposition = !strncasecmp(data, "Content-Disposition", len);
	return 0;
}

static int
header_value(multipart_parser *p, const char *data, size_t len)
{
	size_t i, j;

	if (!st.is_content_disposition)
		return 0;

	if (len < 10 || strncasecmp(data, "form-data", 9))
		return 0;

	for (data += 9, len -= 9; *data == ' ' || *data == ';'; data++, len--);

	if (len < 8 || strncasecmp(data, "name=\"", 6))
		return 0;

	for (data += 6, len -= 6, i = 0; i <= len; i++)
	{
		if (*(data + i) != '"')
			continue;

		for (j = 1; j < sizeof(parts) / sizeof(parts[0]); j++)
			if (!strncmp(data, parts[j], i))
				st.parttype = j;

		break;
	}

	return 0;
}

static int
data_begin_cb(multipart_parser *p)
{
	if (st.parttype == PART_FILEDATA)
	{
		if (!st.sessionid)
			return response(false, "File data without session");

		if (!st.filename)
			return response(false, "File data without name");

		if (!session_access(st.sessionid, "file", st.filename, "write"))
			return response(false, "Access to path denied by ACL");

		st.tempfd = open("/tmp", O_TMPFILE | O_RDWR, S_IRUSR | S_IWUSR);

		if (st.tempfd < 0)
			return response(false, "Failed to create temporary file");
	}

	return 0;
}

static int
data_cb(multipart_parser *p, const char *data, size_t len)
{
	int wlen = len;

	switch (st.parttype)
	{
	case PART_SESSIONID:
		st.sessionid = datadup(data, len);
		break;

	case PART_FILENAME:
		st.filename = canonicalize_path(data, len);
		break;

	case PART_FILEMODE:
		st.filemode = strtoul(data, NULL, 8);
		break;

	case PART_FILEDATA:
		if (write(st.tempfd, data, len) != wlen)
		{
			close(st.tempfd);
			return response(false, "I/O failure while writing temporary file");
		}

		if (!st.filedata)
			st.filedata = !!wlen;

		break;

	default:
		break;
	}

	return 0;
}

static int
data_end_cb(multipart_parser *p)
{
	if (st.parttype == PART_SESSIONID)
	{
		if (!session_access(st.sessionid, "cgi-io", "upload", "write"))
		{
			errno = EPERM;
			return response(false, "Upload permission denied");
		}
	}
	else if (st.parttype == PART_FILEDATA)
	{
		if (st.tempfd < 0)
			return response(false, "Internal program failure");

#if 0
		/* prepare directory */
		for (ptr = st.filename; *ptr; ptr++)
		{
			if (*ptr == '/')
			{
				*ptr = 0;

				if (mkdir(st.filename, 0755))
				{
					unlink(st.tmpname);
					return response(false, "Failed to create destination directory");
				}

				*ptr = '/';
			}
		}
#endif

		if (filecopy())
			return -1;

		return response(true, NULL);
	}

	st.parttype = PART_UNKNOWN;
	return 0;
}

static multipart_parser *
init_parser(void)
{
	char *boundary;
	const char *var;

	multipart_parser *p;
	static multipart_parser_settings s = {
		.on_part_data        = data_cb,
		.on_headers_complete = data_begin_cb,
		.on_part_data_end    = data_end_cb,
		.on_header_field     = header_field,
		.on_header_value     = header_value
	};

	var = getenv("CONTENT_TYPE");

	if (!var || strncmp(var, "multipart/form-data;", 20))
		return NULL;

	for (var += 20; *var && *var != '='; var++);

	if (*var++ != '=')
		return NULL;

	boundary = malloc(strlen(var) + 3);

	if (!boundary)
		return NULL;

	strcpy(boundary, "--");
	strcpy(boundary + 2, var);

	st.tempfd = -1;
	st.filefd = -1;
	st.filemode = 0600;

	p = multipart_parser_init(boundary, &s);

	free(boundary);

	return p;
}

static int
main_upload(int argc, char *argv[])
{
	int rem, len;
	bool done = false;
	char buf[READ_BLOCK];
	multipart_parser *p;

	p = init_parser();

	if (!p)
	{
		errno = EINVAL;
		return response(false, "Invalid request");
	}

	while ((len = read(0, buf, sizeof(buf))) > 0)
	{
		if (!done) {
			rem = multipart_parser_execute(p, buf, len);
			done = (rem < len);
		}
	}

	multipart_parser_free(p);

	return 0;
}

static void
free_charp(char **ptr)
{
	free(*ptr);
}

#define autochar __attribute__((__cleanup__(free_charp))) char

static int
main_download(int argc, char **argv)
{
	char *fields[] = { "sessionid", NULL, "path", NULL, "filename", NULL, "mimetype", NULL };
	unsigned long long size = 0;
	char *p, buf[READ_BLOCK];
	ssize_t len = 0;
	struct stat s;
	int rfd;

	autochar *post = postdecode(fields, 4);
	(void) post;

	if (!fields[1] || !session_access(fields[1], "cgi-io", "download", "read"))
		return failure(403, 0, "Download permission denied");

	if (!fields[3] || !session_access(fields[1], "file", fields[3], "read"))
		return failure(403, 0, "Access to path denied by ACL");

	if (stat(fields[3], &s))
		return failure(404, errno, "Failed to stat requested path");

	if (!S_ISREG(s.st_mode) && !S_ISBLK(s.st_mode))
		return failure(403, 0, "Requested path is not a regular file or block device");

	for (p = fields[5]; p && *p; p++)
		if (!isalnum(*p) && !strchr(" ()<>@,;:[]?.=%-", *p))
			return failure(400, 0, "Invalid characters in filename");

	for (p = fields[7]; p && *p; p++)
		if (!isalnum(*p) && !strchr(" .;=/-", *p))
			return failure(400, 0, "Invalid characters in mimetype");

	rfd = open(fields[3], O_RDONLY);

	if (rfd < 0)
		return failure(500, errno, "Failed to open requested path");

	if (S_ISBLK(s.st_mode))
		ioctl(rfd, BLKGETSIZE64, &size);
	else
		size = (unsigned long long)s.st_size;

	printf("Status: 200 OK\r\n");
	printf("Content-Type: %s\r\n", fields[7] ? fields[7] : "application/octet-stream");

	if (fields[5])
		printf("Content-Disposition: attachment; filename=\"%s\"\r\n", fields[5]);

	if (size > 0) {
		printf("Content-Length: %llu\r\n\r\n", size);
		fflush(stdout);

		while (size > 0) {
			len = sendfile(1, rfd, NULL, size);

			if (len == -1) {
				if (errno == ENOSYS || errno == EINVAL) {
					while ((len = read(rfd, buf, sizeof(buf))) > 0)
						fwrite(buf, len, 1, stdout);

					fflush(stdout);
					break;
				}

				if (errno == EINTR || errno == EAGAIN)
					continue;
			}

			if (len <= 0)
				break;

			size -= len;
		}
	}
	else {
		printf("\r\n");

		while ((len = read(rfd, buf, sizeof(buf))) > 0)
			fwrite(buf, len, 1, stdout);

		fflush(stdout);
	}

	close(rfd);

	return 0;
}

static int
main_backup(int argc, char **argv)
{
	pid_t pid;
	time_t now;
	int r;
	int len;
	int status;
	int fds[2];
	char datestr[16] = { 0 };
	char hostname[64] = { 0 };
	char *fields[] = { "sessionid", NULL };

	autochar *post = postdecode(fields, 1);
	(void) post;

	if (!fields[1] || !session_access(fields[1], "cgi-io", "backup", "read"))
		return failure(403, 0, "Backup permission denied");

	if (pipe(fds))
		return failure(500, errno, "Failed to spawn pipe");

	switch ((pid = fork()))
	{
	case -1:
		return failure(500, errno, "Failed to fork process");

	case 0:
		dup2(fds[1], 1);

		close(0);
		close(2);
		close(fds[0]);
		close(fds[1]);

		r = chdir("/");
		if (r < 0)
			return failure(500, errno, "Failed chdir('/')");

		execl("/sbin/sysupgrade", "/sbin/sysupgrade",
		      "--create-backup", "-", NULL);

		return -1;

	default:
		close(fds[1]);

		now = time(NULL);
		strftime(datestr, sizeof(datestr) - 1, "%Y-%m-%d", localtime(&now));

		if (gethostname(hostname, sizeof(hostname) - 1))
			sprintf(hostname, "OpenWrt");

		printf("Status: 200 OK\r\n");
		printf("Content-Type: application/x-targz\r\n");
		printf("Content-Disposition: attachment; "
		       "filename=\"backup-%s-%s.tar.gz\"\r\n\r\n", hostname, datestr);

		fflush(stdout);

		do {
			len = splice(fds[0], NULL, 1, NULL, READ_BLOCK, SPLICE_F_MORE);
		} while (len > 0);

		waitpid(pid, &status, 0);

		close(fds[0]);

		return 0;
	}
}


static const char *
lookup_executable(const char *cmd)
{
	size_t plen = 0, clen;
	static char path[PATH_MAX];
	char *search, *p;
	struct stat s;

	if (!cmd)
		return NULL;

	clen = strlen(cmd) + 1;

	if (!stat(cmd, &s) && S_ISREG(s.st_mode))
		return cmd;

	search = getenv("PATH");

	if (!search)
		search = "/bin:/usr/bin:/sbin:/usr/sbin";

	p = search;

	do {
		if (*p != ':' && *p != '\0')
			continue;

		plen = p - search;

		if ((plen + clen) >= sizeof(path))
			continue;

		strncpy(path, search, plen);
		sprintf(path + plen, "/%s", cmd);

		if (!stat(path, &s) && S_ISREG(s.st_mode))
			return path;

		search = p + 1;
	} while (*p++);

	return NULL;
}

static int
main_exec(int argc, char **argv)
{
	char *fields[] = { "sessionid", NULL, "command", NULL, "filename", NULL, "mimetype", NULL };
	int i, devnull, status, fds[2];
	bool allowed = false;
	ssize_t len = 0;
	const char *exe;
	char *p, **args;
	pid_t pid;

	autochar *post = postdecode(fields, 4);
	(void) post;

	if (!fields[1] || !session_access(fields[1], "cgi-io", "exec", "read"))
		return failure(403, 0, "Exec permission denied");

	for (p = fields[5]; p && *p; p++)
		if (!isalnum(*p) && !strchr(" ()<>@,;:[]?.=%-", *p))
			return failure(400, 0, "Invalid characters in filename");

	for (p = fields[7]; p && *p; p++)
		if (!isalnum(*p) && !strchr(" .;=/-", *p))
			return failure(400, 0, "Invalid characters in mimetype");

	args = fields[3] ? parse_command(fields[3]) : NULL;

	if (!args)
		return failure(400, 0, "Invalid command parameter");

	/* First check if we find an ACL match for the whole cmdline ... */
	allowed = session_access(fields[1], "file", args[0], "exec");

	/* Now split the command vector... */
	for (i = 1; args[i]; i++)
		args[i][-1] = 0;

	/* Find executable... */
	exe = lookup_executable(args[0]);

	if (!exe) {
		free(args);
		return failure(404, 0, "Executable not found");
	}

	/* If there was no ACL match, check for a match on the executable */
	if (!allowed && !session_access(fields[1], "file", exe, "exec")) {
		free(args);
		return failure(403, 0, "Access to command denied by ACL");
	}

	if (pipe(fds)) {
		free(args);
		return failure(500, errno, "Failed to spawn pipe");
	}

	switch ((pid = fork()))
	{
	case -1:
		free(args);
		close(fds[0]);
		close(fds[1]);
		return failure(500, errno, "Failed to fork process");

	case 0:
		devnull = open("/dev/null", O_RDWR);

		if (devnull > -1) {
			dup2(devnull, 0);
			dup2(devnull, 2);
			close(devnull);
		}
		else {
			close(0);
			close(2);
		}

		dup2(fds[1], 1);
		close(fds[0]);
		close(fds[1]);

		if (chdir("/") < 0) {
			free(args);
			return failure(500, errno, "Failed chdir('/')");
		}

		if (execv(exe, args) < 0) {
			free(args);
			return failure(500, errno, "Failed execv(...)");
		}

		return -1;

	default:
		close(fds[1]);

		printf("Status: 200 OK\r\n");
		printf("Content-Type: %s\r\n",
		       fields[7] ? fields[7] : "application/octet-stream");

		if (fields[5])
			printf("Content-Disposition: attachment; filename=\"%s\"\r\n",
			       fields[5]);

		printf("\r\n");
		fflush(stdout);

		do {
			len = splice(fds[0], NULL, 1, NULL, READ_BLOCK, SPLICE_F_MORE);
		} while (len > 0);

		waitpid(pid, &status, 0);

		close(fds[0]);
		free(args);

		return 0;
	}
}

int main(int argc, char **argv)
{
	if (strstr(argv[0], "cgi-upload"))
		return main_upload(argc, argv);
	else if (strstr(argv[0], "cgi-download"))
		return main_download(argc, argv);
	else if (strstr(argv[0], "cgi-backup"))
		return main_backup(argc, argv);
	else if (strstr(argv[0], "cgi-exec"))
		return main_exec(argc, argv);

	return -1;
}
