
import consts
import general

import esp/esp_timer
export esp_timer, consts

type
  TimerError* = object of OSError
    code*: esp_err_t
  
  BasicTimer* = object 
    ts: Micros

proc createTimer*(
        callback: esp_timer_cb_t, ## !< Function to call when timer expires
        arg: pointer, ## !< Argument to pass to the callback
        dispatch_method: esp_timer_dispatch_t, ## !< Call the callback from task or from ISR
        name: cstring
      ): esp_timer_handle_t =
  ## !< Timer name, used in esp_timer_dump function

  var create_args: esp_timer_create_args_t
  var out_handle: esp_timer_handle_t

  let ret = esp_timer_create(addr(create_args), addr(out_handle))

  if ESP_OK != ret:
    raise newEspError[TimerError]("timer: " & $esp_err_to_name(ret), ret)

  return out_handle


proc microsRaw*(): uint64 {.inline.} =
  return cast[uint64](esp_timer_get_time())

proc micros*(): Micros =
  return Micros(microsRaw())

proc millis*(): Millis =
  return Millis(micros().uint64 div 1000U)

converter toTicks*(ts: Millis): TickType_t =
  return TickType_t(uint32(ts) div portTICK_PERIOD_MS)

converter toMillis*(ts: Micros): Millis =
  return Millis(ts.uint64 div 1_000U)

proc toMicros*(ts: Millis): Micros =
  return Micros(ts.uint64 * 1_000U)

proc delayMillis*(ms: uint64): uint64 =
  var start = millis()
  vTaskDelay(Millis(ms).toTicks())
  var stop = millis()
  return (stop-start).uint64

# void IRAM_ATTR delayMicroseconds(uint32_t us)
proc delayMicros*(us: uint64): uint64 =
  if us.uint64 == 0:
    return 0

  var curr: uint64 = microsRaw()
  var target = curr + us.uint64
  if target < curr: # overflow?
    while curr > target:
      curr = microsRaw()

  while(curr < target):
    curr = microsRaw()

  return target-curr

proc delay*(ts: Millis) = discard delayMillis(ts.uint64)
proc delay*(ts: Micros) = discard delayMicros(ts.uint64)

proc newBasicTimer*(): BasicTimer =
  return BasicTimer(ts: micros())

proc elapsed*(timer: BasicTimer): Micros =
  return micros() - timer.ts

proc waitFor*(timer: BasicTimer, duration: Millis): Millis =
  var curr: Millis = millis()
  let ts: Millis = timer.ts.toMillis()
  let te = ts + duration

  if te <= curr:
    return curr - ts
  else:
    delay(te - curr)
    return micros() - ts

proc waitFor*(timer: BasicTimer, duration: Micros): Micros =
  var curr: Micros = micros()
  let ts: Micros = timer.ts
  let te = ts + duration

  if te <= curr:
    return curr - ts
  else:
    delay(te - curr)
    return micros() - ts

template timeBlock*(n: string, blk: untyped): untyped =
  let t0 = micros()
  blk
  echo n & " took: ", $(micros() - t0), " micros "

template timeBlockDebug*(n: string, blk: untyped): untyped =
  when defined(debugRpcTimes):
    let t0 = micros()
    blk
    echo n & " took: ", $(micros() - t0), " micros "
  else:
    blk
