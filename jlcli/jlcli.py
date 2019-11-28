#!/usr/bin/env python3

"""
Julia CLI frontend
"""

import argparse
import json
import os
import pprint
import re
import socket
import sys
from pathlib import Path

__version__ = "0.1.0"


class ApplicationError(RuntimeError):
    code = 1


class CLIArgumentError(ApplicationError):
    code = 2


def printerror(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def parse_callmain(callmain: str):
    """
    Parse arguments for `callmain` API.

    >>> parse_callmain("PkgName=u-u-i-d:main.function.name") == {
    ...     "pkgname": "PkgName",
    ...     "pkguuid": "u-u-i-d",
    ...     "main": "main.function.name",
    ... }
    True
    """
    # [[../src/workerinitenv/init.jl::callmain]]
    m = re.match(
        """
        (?P<pkgname>[^=]+)
        =
        (?P<pkguuid>[^:]+)
        :
        (?P<main>.+)
        """,
        callmain,
        re.VERBOSE,
    )
    if m:
        return m.groupdict()
    raise CLIArgumentError(
        "Invalid CALLABLE argument. Requires an argument of the form: "
        "PkgName=u-u-i-d:main.function.name"
    )


def default_stdio_path(name):
    try:
        n = getattr(sys, name).fileno()
    except OSError:
        return None
    return f"/proc/{os.getpid()}/fd/{n}"


def default_stdin_path():
    return default_stdio_path("stdin")


def default_stdout_path():
    return default_stdio_path("stdout")


def default_stderr_path():
    stdout = default_stdio_path("stdout")
    stderr = default_stdio_path("stderr")
    if isinstance(stdout, str) and stdout == stderr:
        return ":stdout"
    return stderr


def compile_request(
    eval,
    include,
    callmain,
    callany,
    adhoccli,
    julia,
    project,
    stdin,
    stdout,
    stderr,
    script,
    args,
    usemain,
    ignorereturn,
    **rest,
):
    if not (eval or include or callmain or callany or adhoccli or script):
        raise CLIArgumentError(
            "At least one of `--eval`, `--callmain`, `--callany`, `--adhoccli`"
            " and `script` are required."
        )

    args = args or []
    if eval or include or callmain or adhoccli:
        if script:
            args.insert(0, script)
    elif callany:
        if args:
            raise CLIArgumentError(
                "`--callany` only takes one JSON object as an argument."
            )

    if project:
        project = str(Path(project).resolve())
    else:
        project = None

    def makeparams(**kwargs):
        return dict(
            # Not using dict literal since PEP 448 is available
            # only after Python 3.5:
            julia=julia,
            project=project,
            cwd=str(Path.cwd()),
            usemain=usemain,
            ignorereturn=ignorereturn,
            stdin={"path": stdin},
            stdout={"path": stdout},
            stderr={"to": "stdout"} if stderr == ":stdout" else {"path": stderr},
            **kwargs,
        )

    # https://www.jsonrpc.org/specification#request_object
    if eval:
        request = {
            "jsonrpc": "2.0",
            "method": "eval",
            "params": makeparams(code=eval, args=args),
            "id": 0,
        }
    elif include:
        request = {
            "jsonrpc": "2.0",
            "method": "eval",
            "params": makeparams(
                code="Base.include(@__MODULE__, popfirst!(ARGS))", args=[include] + args
            ),
            "id": 0,
        }
    elif callmain:
        request = {
            "jsonrpc": "2.0",
            "method": "callmain",
            "params": makeparams(args=args, **parse_callmain(callmain)),
            "id": 0,
        }
    elif callany:
        request = {
            "jsonrpc": "2.0",
            "method": "callany",
            "params": makeparams(**parse_callmain(callany), **json.loads(script)),
            "id": 0,
        }
    elif adhoccli:
        request = {
            "jsonrpc": "2.0",
            "method": "adhoccli",
            "params": makeparams(args=args, **parse_callmain(adhoccli)),
            "id": 0,
        }
    elif script:
        request = {
            "jsonrpc": "2.0",
            "method": "run",
            "params": makeparams(script=str(Path(script).resolve()), args=args),
            "id": 0,
        }
    return request, rest


def send_request(request, connection, **kwargs):
    msg = json.dumps(request).encode("utf-8") + b"\n"

    received = []
    with socket.socket(socket.AF_UNIX) as sock:
        sock.connect(connection)
        sock.sendall(msg)
        received.append(sock.recv(4096))
        while received[-1] and b"\n" not in received[-1]:
            received.append(sock.recv(4096))

    got = b"".join(received)
    response = json.loads(got)
    return handle_response(response, **kwargs)


def handle_response(response, print_result):
    # https://www.jsonrpc.org/specification#response_object
    notfound = object()
    rid = response.get("id", notfound)
    if rid != 0:
        printerror("Response ID does not match. Got:", rid)

    result = response.get("result", notfound)
    if result is not notfound:
        stdout = result.get("stdout", None)
        if stdout is not None:
            print(stdout, end="")
        ans = result.get("result", notfound)
        if ans is not notfound and ans is not None and print_result:
            pprint.pprint(ans)
        return

    error = response.get("error", {})
    message = error.get("message", notfound)
    if error is not notfound and message is not notfound:
        data = error.get("data", None)
        if data is None:
            data = {}
        if not isinstance(data, dict):
            if data is not None and print_result:
                pprint.pprint(data)
            printerror(message)
            printerror(f"** Invalid response type of `data`: {type(data)} **")
            return 3

        stdout = data.get("stdout", None)
        if stdout is not None:
            print(stdout, end="")

        backtrace = data.get("backtrace", None)
        if backtrace is not None:
            printerror(backtrace)
        else:
            printerror(message)

        exception = data.get("exception", None)
        if exception is not None and print_result:
            pprint.pprint(exception)
        return 1

    printerror("Invalid response:")
    pprint.pprint(response)
    printerror()
    return 3


def jlcli(**kwargs):
    request, kwargs = compile_request(**kwargs)
    return send_request(request, **kwargs)


def default_connection():
    return Path("~").expanduser() / ".julia" / "jlcli" / "socket"


class CustomFormatter(
    argparse.RawDescriptionHelpFormatter, argparse.ArgumentDefaultsHelpFormatter
):
    pass


def parse_args(args):
    if args is None:
        args = sys.argv[1:]
    parser = argparse.ArgumentParser(
        formatter_class=CustomFormatter,
        description=__doc__,
        usage=(
            "%(prog)s [options] --eval=CODE [args...]\n"
            "       %(prog)s [options] --include=FILE [args...]\n"
            "       %(prog)s [options] --callmain=CALLABLE [args...]\n"
            "       %(prog)s [options] --callany=CALLABLE JSON\n"
            "       %(prog)s [options] --adhoccli=CALLABLE -- [args...]\n"
            "       %(prog)s [options] script [args...]"
        ),
    )
    parser.add_argument("--connection", default=str(default_connection()))
    parser.add_argument("--print-result", action="store_true")
    parser.add_argument("--julia", default="julia")
    parser.add_argument("--project")
    parser.add_argument(
        "--stdin", help="file path to be used for stdin", default=default_stdin_path()
    )
    parser.add_argument(
        "--stdout",
        help="file path to be used for stdout",
        default=default_stdout_path(),
    )
    parser.add_argument(
        "--stderr",
        help="file path to be used for stderr",
        default=default_stderr_path(),
    )
    parser.add_argument("--usemain", action="store_true", default=False)
    parser.add_argument("--ignorereturn", action="store_true", default=False)

    group = parser.add_mutually_exclusive_group()
    group.add_argument("--eval", metavar="CODE")
    group.add_argument(
        "--include",
        metavar="FILE",
        help="""
        Run Julia script FILE.  Note that the namespace is not `Main` unless
        `--usemain` is given.  Use `--ignorereturn` if the last expression
        in FILE may not be JSON serializable.
        """,
    )
    group.add_argument(
        "--callmain",
        metavar="CALLABLE",
        help="""
        CALLABLE should be a string of the form
        `PkgName=u-u-i-d:main.function.name`; i.e.,
        a package name, a literal equal sign `=`, a UUID,
        a literal colon `:`, and the full name of the function
        to be called.
        """,
    )
    group.add_argument(
        "--callany",
        metavar="CALLABLE",
        help="""
        CALLABLE is same as `--callmain`.  This option must be
        followed by a JSON object with an optional key `args` which
        should map to an array and an optional key `kwargs` which
        should map to an object.
        """,
    )
    group.add_argument(
        "--adhoccli",
        metavar="CALLABLE",
        help="""
        CALLABLE is same as `--callmain`.  Arguments after `--` are
        interpreted as positional and keyword arguments to this
        callable.
        """,
    )
    parser.add_argument(
        "script",
        nargs="?",
        help="""
        If the first argument is `script` (i.e., does not start with a
        `-`), all following options are not parsed by `jlcli` and sent
        to `ARGS` of `script`.
        """,
    )
    parser.add_argument(
        "args",
        nargs="*",
        help="""
        `ARGS` for `script`.
        """,
    )
    if len(args) > 0 and not args[0].startswith("-"):
        # When the first argument is `script`, do not handle any other
        # options.
        args.insert(0, "--")
    return parser.parse_args(args)


def main(args=None):
    ns = parse_args(args)

    try:
        sys.exit(jlcli(**vars(ns)))
    except (ApplicationError) as err:
        print(err, file=sys.stderr)
        sys.exit(err.code)


if __name__ == "__main__":
    main()
