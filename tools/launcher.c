#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

static int join_path(char *result, const char *root, const char *suffix)
{
    int count = snprintf(result, PATH_MAX, "%s/%s", root, suffix);
    if (count < 0 || count >= PATH_MAX) {
        errno = ENAMETOOLONG;
        return -1;
    }
    return 0;
}

int main(int argc, char *argv[])
{
    char launch_path[PATH_MAX], executable[PATH_MAX], data[PATH_MAX];
    char game_home[PATH_MAX], support[PATH_MAX];
    uint32_t size = sizeof(launch_path);
    (void)argc;
    const char *home = getenv("HOME");

    if (home == NULL || home[0] != '/' || _NSGetExecutablePath(launch_path, &size) != 0) {
        fputs("Cannot locate the game bundle or your home directory.\n", stderr);
        return 1;
    }

    const char *binary_dir = dirname(launch_path);
    if (join_path(executable, binary_dir, "reVC") != 0 ||
        join_path(data, binary_dir, "../../../GameData") != 0 ||
        chdir(data) != 0) {
        perror("Cannot locate the installed game files");
        return 1;
    }

    /* The engine stores its settings under HOME/Library/Application Support/reVC. */
    if (join_path(support, home, "Library/Application Support") != 0 ||
        join_path(game_home, support, "Hawking Vice City") != 0 ||
        (mkdir(game_home, 0700) != 0 && errno != EEXIST) ||
        setenv("HOME", game_home, 1) != 0) {
        perror("Cannot create the Hawking Vice City save directory");
        return 1;
    }

    argv[0] = executable;
    execv(executable, argv);
    perror("Cannot launch the Hawking Vice City engine");
    return 1;
}
