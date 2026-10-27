"""
Build the bundled demo-native library for the current host platform.
为当前宿主平台构建内置的 demo-native 原生库。
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory


# LibraryFileNames maps every LuaSkills platform key declared in dependencies.yaml to its library file name.
# LibraryFileNames 将 dependencies.yaml 中声明的每个 LuaSkills 平台键映射到对应的库文件名。
LIBRARY_FILE_NAMES = {
    "windows-x64": "demo_native.dll",
    "linux-x64": "libdemo_native.so",
    "linux-arm64": "libdemo_native.so",
    "macos-x64": "libdemo_native.dylib",
    "macos-arm64": "libdemo_native.dylib",
}
# SourceRelativePath is the only C translation unit compiled into the library.
# SourceRelativePath 是编译进库的唯一 C 翻译单元。
SOURCE_RELATIVE_PATH = Path("native") / "demo_native.c"
# NativeRootName is the package-whitelisted directory that receives native/<platform>/<library>.
# NativeRootName 是接收 native/<platform>/<library> 的发布白名单目录。
NATIVE_ROOT_NAME = "native"
# DefaultMacosDeploymentTarget keeps macOS builds loadable on releases older than the build runner.
# DefaultMacosDeploymentTarget 让 macOS 构建产物可在早于构建机的系统版本上加载。
DEFAULT_MACOS_DEPLOYMENT_TARGET = "11.0"
# GnuCompilerNames are probed in order when CC is not set.
# GnuCompilerNames 是未设置 CC 时依次探测的编译器名称。
GNU_COMPILER_NAMES = ("gcc", "clang", "cc")
# MsvcCompilerNames identify compiler drivers that use MSVC-style command lines.
# MsvcCompilerNames 标识使用 MSVC 风格命令行的编译器驱动。
MSVC_COMPILER_NAMES = frozenset({"cl", "clang-cl"})


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Map one operating-system name and machine name to the LuaSkills platform key.
将操作系统名称与机器名称映射为 LuaSkills 平台键。

Args:
    system_name: Value shaped like platform.system(), such as Windows, Linux, or Darwin.
    system_name：形如 platform.system() 的值，例如 Windows、Linux 或 Darwin。
    machine_name: Value shaped like platform.machine(), such as AMD64, x86_64, arm64, or aarch64.
    machine_name：形如 platform.machine() 的值，例如 AMD64、x86_64、arm64 或 aarch64。

Returns:
    Platform key using the same spelling as LuaSkills dependency manifests.
    与 LuaSkills 依赖清单拼写一致的平台键。
"""
def normalize_platform_key(system_name: str, machine_name: str) -> str:
    # SystemKey is the lowercase operating-system prefix of the platform key.
    # SystemKey 是平台键中的小写操作系统前缀。
    system_key = {"windows": "windows", "linux": "linux", "darwin": "macos"}.get(system_name.strip().lower())
    # ArchitectureKey is the CPU suffix of the platform key.
    # ArchitectureKey 是平台键中的 CPU 后缀。
    architecture_key = {
        "amd64": "x64",
        "x86_64": "x64",
        "x64": "x64",
        "arm64": "arm64",
        "aarch64": "arm64",
    }.get(machine_name.strip().lower())
    if system_key is None or architecture_key is None:
        raise RuntimeError(f"Unsupported host platform: {system_name}/{machine_name}")
    return f"{system_key}-{architecture_key}"


"""
Return the LuaSkills platform key of the running Python interpreter.
返回当前 Python 解释器所在主机的 LuaSkills 平台键。
"""
def host_platform_key() -> str:
    return normalize_platform_key(platform.system(), platform.machine())


"""
Return the library file name declared for one platform key.
返回某个平台键所声明的库文件名。

Args:
    platform_key: LuaSkills platform key such as windows-x64.
    platform_key：LuaSkills 平台键，例如 windows-x64。

Returns:
    Library file name used in native/<platform>/ and in the dependency export.
    在 native/<platform>/ 与依赖导出中使用的库文件名。
"""
def library_file_name(platform_key: str) -> str:
    # FileName is absent for platforms that dependencies.yaml does not declare.
    # FileName 对于 dependencies.yaml 未声明的平台为空。
    file_name = LIBRARY_FILE_NAMES.get(platform_key)
    if file_name is None:
        raise RuntimeError(
            f"Platform {platform_key} has no demo-native package; declared platforms: {', '.join(sorted(LIBRARY_FILE_NAMES))}"
        )
    return file_name


"""
Return the package-relative path of the library built for one platform key.
返回某个平台键对应构建产物的包内相对路径。
"""
def library_relative_path(platform_key: str) -> Path:
    return Path(NATIVE_ROOT_NAME) / platform_key / library_file_name(platform_key)


"""
Select the C compiler and its command-line flavor.
选择 C 编译器及其命令行风格。

Args:
    environ: Environment mapping whose CC value, when set, names the compiler program.
    environ：环境变量映射；设置 CC 时由其指定编译器程序。
    platform_key: Host platform key used to decide whether MSVC is an accepted fallback.
    platform_key：用于判断是否允许回退到 MSVC 的宿主平台键。

Returns:
    Tuple of the resolved compiler program and either "gnu" or "msvc".
    已解析编译器程序与 "gnu" 或 "msvc" 风格组成的元组。
"""
def resolve_compiler(environ: dict[str, str], platform_key: str) -> tuple[str, str]:
    # Requested is the explicit CC override; it names one program without extra arguments.
    # Requested 是显式 CC 覆盖值；它只指定一个不带额外参数的程序。
    requested = environ.get("CC", "").strip()
    # Candidates are probed in order until one exists on PATH.
    # Candidates 会依次探测，直到在 PATH 中找到一个可用程序。
    candidates = [requested] if requested else list(GNU_COMPILER_NAMES)
    if not requested and platform_key.startswith("windows"):
        candidates.append("cl")
    for candidate in candidates:
        # ProgramPath is the absolute executable path resolved from PATH or the given path.
        # ProgramPath 是从 PATH 或给定路径解析出的可执行文件绝对路径。
        program_path = shutil.which(candidate)
        if program_path is None:
            continue
        # ProgramName drops directories and the Windows executable suffix before flavor detection.
        # ProgramName 在识别命令风格前去掉目录与 Windows 可执行文件后缀。
        program_name = Path(program_path).name.lower()
        if program_name.endswith(".exe"):
            program_name = program_name[:-4]
        return program_path, "msvc" if program_name in MSVC_COMPILER_NAMES else "gnu"
    if requested:
        raise RuntimeError(f"CC names a compiler that was not found: {requested}")
    raise RuntimeError(
        f"No C compiler found; install one of {', '.join(candidates)} or set CC to a compiler program"
    )


"""
Build the exact compiler command line for one platform and compiler flavor.
为指定平台与编译器风格构建精确的编译命令行。

Args:
    program: Compiler program returned by resolve_compiler.
    program：resolve_compiler 返回的编译器程序。
    flavor: Either "gnu" or "msvc".
    flavor："gnu" 或 "msvc"。
    platform_key: Target platform key, which equals the host platform key.
    platform_key：目标平台键，与宿主平台键相同。
    source_path: Absolute path of the C source file.
    source_path：C 源文件的绝对路径。
    output_name: Library file name written into the working directory.
    output_name：写入工作目录的库文件名。
    environ: Environment mapping that may override the macOS deployment target.
    environ：可覆盖 macOS 部署目标版本的环境变量映射。

Returns:
    Argument list passed directly to subprocess without a shell.
    不经过 shell、直接传给 subprocess 的参数列表。
"""
def compiler_command(
    program: str,
    flavor: str,
    platform_key: str,
    source_path: Path,
    output_name: str,
    environ: dict[str, str],
) -> list[str]:
    if flavor == "msvc":
        # MSVC links the static CRT so the DLL does not need a separate VC++ runtime.
        # MSVC 链接静态 CRT，使 DLL 不依赖单独安装的 VC++ 运行库。
        return [program, "/nologo", "/O2", "/MT", "/LD", str(source_path), f"/Fe{output_name}"]

    # Command holds the GCC/Clang-compatible flags shared by every platform.
    # Command 保存所有平台共用的 GCC/Clang 兼容参数。
    command = [program, "-O2", "-std=c99", "-Wall"]
    if platform_key.startswith("windows"):
        command.append("-shared")
        # ProgramName decides whether the MinGW libgcc runtime must be linked statically.
        # ProgramName 用于判断是否需要静态链接 MinGW 的 libgcc 运行时。
        program_name = Path(program).name.lower()
        if "gcc" in program_name:
            command.append("-static-libgcc")
    elif platform_key.startswith("macos"):
        # DeploymentTarget is the oldest macOS release allowed to load the library.
        # DeploymentTarget 是允许加载该库的最低 macOS 版本。
        deployment_target = environ.get("MACOSX_DEPLOYMENT_TARGET", "").strip() or DEFAULT_MACOS_DEPLOYMENT_TARGET
        command.extend(
            [
                "-dynamiclib",
                f"-mmacosx-version-min={deployment_target}",
                "-install_name",
                f"@rpath/{output_name}",
            ]
        )
    else:
        command.extend(["-shared", "-fPIC"])
    command.extend(["-o", output_name, str(source_path)])
    return command


"""
Compile the library in a temporary directory and copy only the library into native/<platform>/.
在临时目录中编译库，并只把库文件复制到 native/<platform>/。

Args:
    root: Repository root containing native/demo_native.c.
    root：包含 native/demo_native.c 的仓库根目录。
    platform_key: Host platform key that selects the output directory and file name.
    platform_key：用于选择输出目录与文件名的宿主平台键。

Returns:
    Absolute path of the copied library.
    已复制库文件的绝对路径。
"""
def build_library(root: Path, platform_key: str) -> Path:
    # SourcePath is the C source compiled for the host platform.
    # SourcePath 是为宿主平台编译的 C 源文件。
    source_path = (root / SOURCE_RELATIVE_PATH).resolve()
    if not source_path.is_file():
        raise RuntimeError(f"Native source file is missing: {SOURCE_RELATIVE_PATH.as_posix()}")
    # OutputPath is the bundled payload path declared by dependencies.yaml.
    # OutputPath 是 dependencies.yaml 声明的内置载荷路径。
    output_path = root / library_relative_path(platform_key)
    # Environ is copied once so compiler selection and flags read the same snapshot.
    # Environ 只复制一次，使编译器选择与参数读取同一份快照。
    environ = dict(os.environ)
    program, flavor = resolve_compiler(environ, platform_key)

    # WorkDirectory isolates objects, import libraries, and export files from the package tree.
    # WorkDirectory 将目标文件、导入库与导出文件隔离在发布目录之外。
    with TemporaryDirectory(prefix="demo-native-") as work_directory:
        # Command is executed without a shell so paths with spaces stay intact.
        # Command 不经过 shell 执行，含空格的路径保持完整。
        command = compiler_command(
            program,
            flavor,
            platform_key,
            source_path,
            output_path.name,
            environ,
        )
        # CompilerResult forwards compiler diagnostics to stderr so stdout carries only the output path.
        # CompilerResult 把编译器诊断转发到 stderr，使 stdout 只输出产物路径。
        compiler_result = subprocess.run(command, cwd=work_directory, stdout=sys.stderr, check=False)
        if compiler_result.returncode != 0:
            raise RuntimeError(f"Compiler failed with exit code {compiler_result.returncode}: {' '.join(command)}")
        # BuiltPath is the library produced inside the isolated working directory.
        # BuiltPath 是隔离工作目录内生成的库文件。
        built_path = Path(work_directory) / output_path.name
        if not built_path.is_file():
            raise RuntimeError(f"Compiler did not produce {output_path.name}")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(built_path, output_path)
    return output_path.resolve()


"""
Parse command-line arguments for the native library builder.
解析原生库构建脚本的命令行参数。
"""
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build native/<platform>/<library> for the current host platform. Set CC to choose the compiler."
    )
    return parser.parse_args()


"""
Build the host library and print its absolute path.
构建宿主平台库并输出其绝对路径。
"""
def main() -> int:
    parse_args()
    try:
        # PlatformKey selects the declared package entry for the running host.
        # PlatformKey 选择当前主机对应的已声明包条目。
        platform_key = host_platform_key()
        # OutputPath is the bundled payload ready for packaging and debugging.
        # OutputPath 是可直接用于打包与调试的内置载荷。
        output_path = build_library(repo_root(), platform_key)
    except RuntimeError as error:
        print(f"Native build failed: {error}", file=sys.stderr)
        return 1
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
