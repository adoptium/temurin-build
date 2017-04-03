import os

BUILD_HOME = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "../../"))
USER_HOME = os.environ.get("HOME")
ERROR_CODES = {
    "ERROR_GENERAL": 100,
    "ERROR_TIMEOUT": 101,
    "ERROR_STYLE": 102,
    "ERROR_BUILD": 103,
    "ERROR_SANITY": 104
}

