import threading

from runtime import exec as runtime_exec
from runtime import protocol
from runtime import state


def main_loop():
    command_queue = protocol.command_queue()

    while True:
        message = command_queue.get()
        if message is None:
            break

        msg_type = message.get("type")
        if msg_type == "exec":
            runtime_exec.execute_code(message.get("code", ""))
        elif msg_type == "set_context":
            state.set_context(message.get("value", ""))
            protocol.write_message({"type": "context_set"})
        elif msg_type == "set_file_sources":
            state.set_file_sources(message.get("paths", []))
            protocol.write_message({"type": "file_sources_set"})
        elif msg_type == "reset_final":
            state.reset_final_result()
            state.reset_tracking()
            protocol.write_message({"type": "final_reset"})


def run():
    protocol.write_message({"type": "ready"})
    reader = threading.Thread(target=protocol.stdin_reader_loop, daemon=True)
    reader.start()

    try:
        main_loop()
    finally:
        protocol.shutdown_executor()
