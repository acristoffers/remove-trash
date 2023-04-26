#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <wordexp.h>

static size_t size = 0;

int EndsWith(const char *str, const char *suffix) {
  if (!str || !suffix) {
    return 0;
  }

  size_t lenstr = strlen(str);
  size_t lensuffix = strlen(suffix);

  if (lensuffix > lenstr) {
    return 0;
  }

  return strncmp(str + lenstr - lensuffix, suffix, lensuffix) == 0;
}

size_t folder_size(const char *dir_name) {
  DIR *d = opendir(dir_name);

  if (!d) {
    fprintf(stderr, "Cannot open '%s': %s\n", dir_name, strerror(errno));
    return 0;
  }

  uint64_t r = 0;

  while (1) {
    struct dirent *entry = readdir(d);

    if (!entry) {
      break;
    }

    char path[PATH_MAX];
    int length = snprintf(path, PATH_MAX, "%s/%s", dir_name, entry->d_name);

    if (length >= PATH_MAX) {
      fprintf(stderr, "Path length has got too long.\n");
      continue;
    }

    if (entry->d_type == DT_DIR) {
      if (strcmp(entry->d_name, "..") != 0 && strcmp(entry->d_name, ".") != 0) {
        r += folder_size(path);
      }
    } else {
      struct stat st;
      stat(path, &st);
      r += st.st_size;
    }
  }

  if (closedir(d)) {
    fprintf(stderr, "Could not close '%s': %s\n", dir_name, strerror(errno));
  }

  return r;
}

void recurse_dir(const char *dir_name) {
  DIR *d = opendir(dir_name);

  if (!d) {
    fprintf(stderr, "Cannot open '%s': %s\n", dir_name, strerror(errno));
    return;
  }

  while (1) {
    struct dirent *entry = readdir(d);

    if (!entry) {
      break;
    }

    uint8_t c1 = strcmp(entry->d_name, ".DS_Store") == 0;
    uint8_t c2 = strcmp(entry->d_name, "Thumbs.db") == 0;
    uint8_t c3 = strcmp(entry->d_name, ".sass-cache") == 0;
    uint8_t c4 = strcmp(entry->d_name, ".gradle") == 0;
    uint8_t c5 = strcmp(entry->d_name, ".textpadtmp") == 0;
    uint8_t c6 = EndsWith(entry->d_name, ".bak");
    uint8_t c7 = entry->d_name[0] == '~';
    uint8_t c8 = strcmp(entry->d_name, ".mypy_cache") == 0;
    uint8_t c9 = strcmp(entry->d_name, "__pycache__") == 0;
    uint8_t c10 = strcmp(entry->d_name, ".cache") == 0;
    uint8_t c11 = strcmp(entry->d_name, "build") == 0;

    if (c1 || c2 || c3 || c4 || c5 || c6 || c7 || c8 || c9 || c10 || c11) {
      char path[PATH_MAX];
      int length = snprintf(path, PATH_MAX, "%s/%s", dir_name, entry->d_name);

      if (length >= PATH_MAX) {
        fprintf(stderr, "Path length has got too long.\n");
        continue;
      }

      if (entry->d_type == DT_DIR) {
        size += folder_size(path);
      } else {
        struct stat st;
        stat(path, &st);
        size += st.st_size;
      }

      unlink(path);

      continue;
    }

    if (entry->d_type == DT_DIR) {
      if (strcmp(entry->d_name, "..") != 0 && strcmp(entry->d_name, ".") != 0) {
        char path[PATH_MAX];
        int length = snprintf(path, PATH_MAX, "%s/%s", dir_name, entry->d_name);

        if (length >= PATH_MAX) {
          fprintf(stderr, "Path length has got too long.\n");
          continue;
        }

        recurse_dir(path);
      }
    }
  }

  if (closedir(d)) {
    fprintf(stderr, "Could not close '%s': %s\n", dir_name, strerror(errno));
  }
}

void pretty_bytes(char *buf, uint bytes) {
  const char *suffixes[7];
  suffixes[0] = "B";
  suffixes[1] = "KB";
  suffixes[2] = "MB";
  suffixes[3] = "GB";
  suffixes[4] = "TB";
  suffixes[5] = "PB";
  suffixes[6] = "EB";

  uint s = 0; // which suffix to use
  double count = bytes;

  while (count >= 1024 && s < 7) {
    s++;
    count /= 1024;
  }

  if (count - floor(count) == 0.0) {
    sprintf(buf, "%d %s", (int)count, suffixes[s]);
  } else {
    sprintf(buf, "%.2f %s", count, suffixes[s]);
  }
}

int main(int argc, char *argv[]) {
  wordexp_t e_path;

  if (argc > 1) {
    wordexp(argv[1], &e_path, 0);
  } else {
    wordexp(".", &e_path, 0);
  }

  char path[PATH_MAX];
  realpath(e_path.we_wordv[0], path);

  recurse_dir(path);

  char sizebuf[PATH_MAX];
  pretty_bytes(sizebuf, size);
  printf("Freed %s\n", sizebuf);

  return 0;
}
