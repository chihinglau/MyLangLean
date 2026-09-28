@echo off
chcp 65001 >nul
setlocal
rem MyLangLean 字幕工坊一键启动脚本
rem 自动使用仓库内置 Python 虚拟环境，首次运行自动安装依赖。

set "HERE=%~dp0"
set "ROOT=%HERE%..\..\"
set "PY=%ROOT%.tools\venvs\mll\Scripts\python.exe"

if not exist "%PY%" (
  echo [错误] 未找到内置 Python：%PY%
  echo 请先在仓库中运行工具链初始化，或安装 Python 3.10 后重建该虚拟环境。
  pause
  exit /b 1
)

rem 首次运行安装依赖（faster-whisper / PyAV），走清华镜像。
"%PY%" -c "import faster_whisper" 2>nul
if errorlevel 1 (
  echo [初始化] 正在安装依赖，仅首次运行需要，请稍候……
  "%PY%" -m pip install -r "%HERE%requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple
  if errorlevel 1 (
    echo [错误] 依赖安装失败，请检查网络后重试。
    pause
    exit /b 1
  )
)

rem 模型从 HuggingFace 国内镜像下载，下载完成后可离线使用。
if "%HF_ENDPOINT%"=="" set "HF_ENDPOINT=https://hf-mirror.com"
set "PYTHONPATH=%HERE%."

"%PY%" "%HERE%mll_subtitles\studio.py"
if errorlevel 1 pause
endlocal
