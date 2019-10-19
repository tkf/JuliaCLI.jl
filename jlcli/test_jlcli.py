import os
import shlex

import pytest

from jlcli import CLIArgumentError, compile_request, handle_response, parse_args


def compile_request_from_cliargs(cliargs):
    request, kwargs = compile_request(**vars(parse_args(shlex.split(cliargs))))
    assert request["jsonrpc"] == "2.0"
    return request


def test_require_one_command():
    with pytest.raises(CLIArgumentError):
        compile_request_from_cliargs("")


def test_require_only_one_command():
    with pytest.raises(SystemExit):
        compile_request_from_cliargs(
            """--callany='Statistics=10745b16-79ce-11e8-11f9-7d13ad32a3b2:std'"""
            """ --eval=CODE --"""
        )


def test_request_eval():
    request = compile_request_from_cliargs("--eval=CODE a b c")
    assert request["params"]["code"] == "CODE"
    assert request["params"]["args"] == ["a", "b", "c"]


def test_request_callmain():
    request = compile_request_from_cliargs(
        "--callmain=PkgName=u-u-i-d:main.function.name a b c"
    )
    assert request["params"]["pkgname"] == "PkgName"
    assert request["params"]["pkguuid"] == "u-u-i-d"
    assert request["params"]["main"] == "main.function.name"
    assert request["params"]["args"] == ["a", "b", "c"]


def test_request_callany():
    request = compile_request_from_cliargs(
        """--callany='Statistics=10745b16-79ce-11e8-11f9-7d13ad32a3b2:std'"""
        """ '{"args":[[1,2,3]]}'"""
    )
    assert request["params"]["pkgname"] == "Statistics"
    assert request["params"]["pkguuid"] == "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
    assert request["params"]["main"] == "std"
    assert request["params"]["args"] == [[1, 2, 3]]


def test_request_adhoccli():
    request = compile_request_from_cliargs(
        """--print-result --adhoccli='Unicode=4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5:normalize'"""
        """ -- JuLiA --casefold"""
    )
    assert request["params"]["pkgname"] == "Unicode"
    assert request["params"]["pkguuid"] == "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
    assert request["params"]["main"] == "normalize"
    assert request["params"]["args"] == ["JuLiA", "--casefold"]


def test_request_script():
    scriptfullpath = os.devnull
    request = compile_request_from_cliargs(scriptfullpath + " -h")
    assert request["params"]["script"] == scriptfullpath
    assert request["params"]["args"] == ["-h"]


def handle(**response):
    response["id"] = 0
    return handle_response(response, print_result=True)


def test_response_stdout(capsys):
    err = handle(result={"stdout": "hello"})
    captured = capsys.readouterr()
    assert captured.out == "hello"
    assert not err


def test_response_result(capsys):
    err = handle(result={"result": {"some": "result"}})
    captured = capsys.readouterr()
    assert "some" in captured.out
    assert "result" in captured.out
    assert not err


def test_response_error(capsys):
    err = handle(error={"message": "hello"})
    captured = capsys.readouterr()
    assert captured.err == "hello\n"
    assert err


def test_response_invalid(capsys):
    err = handle()
    captured = capsys.readouterr()
    assert "Invalid response:" in captured.err
    assert err
