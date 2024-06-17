#include <stdint.h>

typedef uint32_t u32;

enum UpdateResult {
  keep_running,
  stop_running,
};

struct Event {
  enum Tag {
    key_down,
  } tag;
  union Data {
    struct KeyDown {
      u32 key;
    } key_down;
  } data;
};

void init();
void onWindowClose(void *window_handle);
void receiveEvent(struct Event *event);
enum UpdateResult update();
void kill();
