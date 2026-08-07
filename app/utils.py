import os
import platform
import socket
import time

START_TIME = time.time()


def get_uptime():
    """
    Human-readable application uptime.
    """

    seconds = int(time.time() - START_TIME)

    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60

    return f"{hours:02d}h {minutes:02d}m {secs:02d}s"


def get_system_info():
    """
    Returns runtime information.
    """

    return {
        "hostname": socket.gethostname(),
        "platform": platform.system(),
        "platform_release": platform.release(),
        "python_version": platform.python_version(),
        "architecture": platform.machine(),
        "cpu_count": os.cpu_count(),
    }


def status_icon(value: bool):
    """
    Returns dashboard icon.
    """

    return "🟢" if value else "🔴"
