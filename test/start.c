#include <stddef.h>

void caml_startup(char** argv);

char* argv[] = {"empty", NULL};

int main() {
    caml_startup(argv);
    return 0;
}