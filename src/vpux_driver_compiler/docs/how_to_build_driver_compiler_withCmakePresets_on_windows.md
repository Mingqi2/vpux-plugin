# How to build Driver Compiler with cmake presets on Windows

## Dependencies

Before you start to build Driver Compiler targets, please make sure you have installed the necessary components. After installation, please make sure they are available from system enviroment path.

- Hardware:
    - Minimum requirements: 40 GB of disk space.

- Software:
    - [CMake](https://cmake.org/download/) 3.13 or higher
    - Microsoft Visual Studio 2019 (recommended) or higher, version 16.3 or later
        > **Notice**: Windows SDK and spectre libraries are required for building OpenVINO and NPU-Plugin. Install them via Visual Studio Installer: Modify -> Individual components -> Search components: "Windows SDK" and "Spectre x64/x86 latest".
    - Python 3.9 - 3.12
    - Git for Windows (requires installing `git lfs`)
    - Ccache (Download latest version of ccache binaries or build from source code on this [link](https://github.com/ccache/ccache/releases))
    - Ninja (Install it via Visual Studio Installer or "Getting Ninja" section on this [link](https://ninja-build.org/))

> Notice: Ccache and Ninja are required for the build options defined in the CMake Presets. Therefore, both of these tools are necessary. If you are unable to install them, please remove and update the relevant sections in [CMakePresets.json](../../../CMakePresets.json#L5).


## Using CMakePresets to build

#### Using CMakePresets to build and using NPU-Plugin as an extra module of OpenVINO

Here provides a default pre-configured CMake presets for users named: "npuCidReleaseXXX", `npuCidReleaseLinux` for Linux and `npuCidReleaseWindows` for Windows. The setting is to build [NPU-Plugin Project] as an extra module of [OpenVINO Project]. In this case, `NPU_PLUGIN_HOME` environment variable must be set.

All instructions are perfromed on **x64 Native Tools Command Prompt for VS XXXX(run as administrator)**.

1. Clone repos:
    <details>
    <summary>Executed in x64 Native Tools Command Prompt for VS XXXX(run as administrator)</summary>

    ```sh
        # set the proxy, if required.
        # set  http_proxy=xxxx
        # set  https_proxy=xxxx

        cd C:\workspace(Just an example, you could use your own branch/tag/commit.)
        git clone https://github.com/openvinotoolkit/openvino.git 
        cd openvino
        git checkout -b master origin/master (Just an example, you could use your own branch/tag/commit.)
        git submodule update --init --recursive

        cd C:\workspace (Just an example, you could use your own branch/tag/commit.)
        git clone https://github.com/openvinotoolkit/npu_plugin.git
        cd npu_plugin
        git checkout -b develop origin/develop (Just an example, you could use your own branch/tag/commit.)
        git submodule update --init --recursive
    ```
    </details>

    > Notice: Please place the cloned repositories in the shortest possible path.

2. Set environment variables and create a symlink for a preset file in OpenVINO Project root:
    <details>
    <summary>Executed in x64 Native Tools Command Prompt for VS XXXX(run as administrator)</summary>
    
    ```sh
        # set the enviroment variables
        set OPENVINO_HOME=C:\workspace\openvino (need change to your own path)
        set NPU_PLUGIN_HOME=C:\workspace\npu_plugin (need change to your own path)

        cd %OPENVINO_HOME%
        mklink .\CMakePresets.json %NPU_PLUGIN_HOME%\CMakePresets.json
    ```
    </details>

    > Notice: Please make sure you do not have CMakePresets.json before you use `mklink .\CMakePresets.json %NPU_PLUGIN_HOME%\CMakePresets.json`.

3. Build with the following commands:

    Before build with the following instructions, please make sure `OPENVINO_HOME` and `NPU_PLUGIN_HOME` enviroment variables have been set..

    <details>
    <summary>Executed in x64 Native Tools Command Prompt for VS XXXX</summary>
    
    ```sh
        cd %OPENVINO_HOME%
        cmake --preset npuCidReleaseWindows
        cd build-x86_64\Release\
        cmake --build .\ --target compilerTest profilingTest vpuxCompilerL0Test loaderTest
    ```
    </details>
    
    The defined build option for npuCidReleaseWindows cmake preset is listed [here](../../../CMakePresets.json#L280). For additional information about its build options, please refer to section `2.2 Build instructions notes` in [how to build Driver Compiler on windows](./how_to_build_driver_compiler_on_windows.md).

    > Notice: If you build Driver compiler using cmake presets and ccache is not installed on this device, the build will fail with the error: `CreateProcess failed: The system cannot find the file specified`during `cmake --build ...` on Windows.

4. (Optional) Prepare final Driver Compiler package for driver:

    <details>
    <summary>Instructions</summary>

    All Driver Compiler related targets have now been generated in `%OPENVINO_HOME%\bin\intel\Release` folder, where the binary npu_driver_compiler.dll can be found. The following instructions are provided to pack Driver Compiler related targets to the specified location.

    ```sh
        #install Driver compiler related targets to current path. A `cid` folder will be generated to `%OPENVINO_HOME%\build-x86_64`.
        cd %OPENVINO_HOME%\build-x86_64
        cmake --install .\ --prefix .\ --component CiD


        # or to get a related compressed file. A RELEASE-CiD.zip compressed file will be generated to `%OPENVINO_HOME%\build-x86_64\`.
        cpack -D CPACK_COMPONENTS_ALL=CiD -D CPACK_CMAKE_GENERATOR=Ninja -D CPACK_PACKAGE_FILE_NAME="RELEASE" -G "ZIP"
    ```
    </details>

5. (Optional) Instruction notes about TBB:

    <details>
    <summary>5.1 Default build mode</summary>

    Nowadays the Driver Compiler is building with TBB mode as default using `-D THREADING=TBB`.
    
    You can also use Sequential mode `-D THREADING=SEQ` to compile. More info about SEQ mode, please refer to this [file](https://github.com/openvinotoolkit/openvino/blob/0ebff040fd22daa37612a82fdf930ffce4ebb099/docs/dev/cmake_options_for_custom_compilation.md#options-affecting-binary-size).

    </details>

    <details>
    <summary>5.2 Use different TBB version</summary>

    When use TBB mode in build option, the default TBB is downloaded by [OpenVINO Project], located in `%OPENVINO_HME%\temp\tbb`.

    If you wish to build with a specific version of TBB, you can download it from [oneTBB Project] and unzip its [release package](https://github.com/oneapi-src/oneTBB/releases). Then, use the `-D ENABLE_SYSTEM_TBB=OFF -D TBBROOT=C:\Users\Local_Admin\workspace\path\to\downloaded\tbb` option to build.
    
    If you would like to build TBB on your own, please refer to [INSTALL.md](https://github.com/oneapi-src/oneTBB/blob/master/INSTALL.md#build-onetbb) in [oneTBB Project] and add `-D CMAKE_MSVC_RUNTIME_LIBRARY="MultiThreaded"` in build option.

    </details>

### Note

1. Presets step for "npuCidReleaseWindows" need to be built in [OpenVINO Project] folder. The defined build directory for "npuCidReleaseWindows" preset is %OPENVINO_HOME%\build-x86_64\Release.
2. The presets are configured to use Ninja as default generator, so installing Ninja package is an extra requirement.
3. Currently, preset for "npuCidReleaseWindows" will build the smallest size targrts of Driver Compiler. If the user wishes to build Driver Compiler and other targets, can driectly inherit "cid" preset and enable the needed build option to self configuration presets.

[OpenVINO Project]: https://github.com/openvinotoolkit/openvino
[NPU-Plugin Project]: https://github.com/openvinotoolkit/npu_plugin
[oneTBB Project]: https://github.com/oneapi-src/oneTBB
