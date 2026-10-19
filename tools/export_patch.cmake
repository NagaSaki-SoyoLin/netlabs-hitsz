cmake_minimum_required(VERSION 3.10)

# Run with `cmake -P tools/export_patch.cmake`; no build configuration is needed.
get_filename_component(NET_LAB_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)
set(NET_LAB_BASE_TAG "net-lab-base")
set(NET_LAB_PATCH "${NET_LAB_ROOT}/commit.patch")

function(export_error reason)
    message(FATAL_ERROR
        "${reason}\n\n本次未生成新的 commit.patch。若已有旧补丁，请处理上述问题后重新生成。")
endfunction()

if(NOT EXISTS "${NET_LAB_ROOT}/.git")
    export_error(
        "当前 net-lab 不含 Git 仓库信息。请按照实验指导书，使用 git clone 获取课程仓库。")
endif()

find_program(NET_LAB_GIT NAMES git)
if(NOT NET_LAB_GIT)
    export_error("未找到 Git。请先安装 Git，并确认终端可以执行 git --version。")
endif()

function(net_lab_git output_variable)
    execute_process(
        COMMAND "${NET_LAB_GIT}" --no-pager ${ARGN}
        WORKING_DIRECTORY "${NET_LAB_ROOT}"
        RESULT_VARIABLE git_result
        OUTPUT_VARIABLE git_output
        ERROR_VARIABLE git_error
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NOT "${git_result}" STREQUAL "0")
        export_error("Git 命令执行失败：${ARGN}\n${git_error}")
    endif()
    set(${output_variable} "${git_output}" PARENT_SCOPE)
endfunction()

# Use the tag ref explicitly, so a branch with the same name cannot replace it.
execute_process(
    COMMAND "${NET_LAB_GIT}" rev-parse --verify
        "refs/tags/${NET_LAB_BASE_TAG}^{commit}"
    WORKING_DIRECTORY "${NET_LAB_ROOT}"
    RESULT_VARIABLE base_result
    OUTPUT_VARIABLE NET_LAB_BASE_COMMIT
    ERROR_VARIABLE base_error
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT "${base_result}" STREQUAL "0")
    export_error(
        "未找到课程初始版本标签 ${NET_LAB_BASE_TAG}。请在项目根目录执行：\n  git fetch origin tag ${NET_LAB_BASE_TAG}\n若 origin 是个人仓库，请改用课程仓库的远程名。\n${base_error}")
endif()

net_lab_git(NET_LAB_HEAD rev-parse --verify HEAD)
execute_process(
    COMMAND "${NET_LAB_GIT}" merge-base --is-ancestor
        "${NET_LAB_BASE_COMMIT}" "${NET_LAB_HEAD}"
    WORKING_DIRECTORY "${NET_LAB_ROOT}"
    RESULT_VARIABLE ancestor_result
    ERROR_VARIABLE ancestor_error
)
if("${ancestor_result}" STREQUAL "1")
    export_error(
        "当前提交不是从 ${NET_LAB_BASE_TAG} 开始开发的。请先备份自己的代码，再按实验指导书将实验修改迁移到课程初始版本。")
elseif(NOT "${ancestor_result}" STREQUAL "0")
    export_error("无法检查当前提交与课程初始版本的关系。\n${ancestor_error}")
endif()

# HEAD excludes both staged changes and untracked files. Reject either so that
# students cannot accidentally export an incomplete implementation.
net_lab_git(NET_LAB_STATUS status --porcelain=v1 --untracked-files=all)
if(NOT "${NET_LAB_STATUS}" STREQUAL "")
    export_error(
        "仍有未提交的修改或未跟踪文件：\n${NET_LAB_STATUS}\n请核对 git status，将必要的实验文件 git add 后 git commit。无关文件请移到项目外，或加入适当的忽略规则。")
endif()

net_lab_git(NET_LAB_CHANGED_FILES diff --name-status --no-renames --no-color
    --no-ext-diff --no-textconv "${NET_LAB_BASE_COMMIT}" "${NET_LAB_HEAD}" --)
if("${NET_LAB_CHANGED_FILES}" STREQUAL "")
    export_error("当前已提交代码与 ${NET_LAB_BASE_TAG} 相同，没有可导出的实验修改。")
endif()

# Write a temporary file directly through Git. This preserves patch bytes on
# Windows as well as Linux and leaves an earlier patch intact on failure.
string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef NET_LAB_NONCE)
set(NET_LAB_TEMP_PATCH "${NET_LAB_ROOT}/.commit.patch-${NET_LAB_NONCE}.tmp")
execute_process(
    COMMAND "${NET_LAB_GIT}" diff --binary --full-index --no-color
        --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/
        "--output=${NET_LAB_TEMP_PATCH}"
        "${NET_LAB_BASE_COMMIT}" "${NET_LAB_HEAD}" --
    WORKING_DIRECTORY "${NET_LAB_ROOT}"
    RESULT_VARIABLE patch_result
    ERROR_VARIABLE patch_error
)
if(NOT "${patch_result}" STREQUAL "0")
    file(REMOVE "${NET_LAB_TEMP_PATCH}")
    export_error("导出补丁失败。\n${patch_error}")
endif()

file(RENAME "${NET_LAB_TEMP_PATCH}" "${NET_LAB_PATCH}")
message(STATUS "已生成 ${NET_LAB_PATCH}")
message(STATUS "初始版本：${NET_LAB_BASE_TAG} (${NET_LAB_BASE_COMMIT})")
message(STATUS "当前提交：${NET_LAB_HEAD}")
string(REPLACE "\r\n" "\n" NET_LAB_CHANGED_FILES "${NET_LAB_CHANGED_FILES}")
string(REPLACE "\r" "\n" NET_LAB_CHANGED_FILES "${NET_LAB_CHANGED_FILES}")
string(REPLACE "\n" ";" NET_LAB_CHANGED_FILE_LINES "${NET_LAB_CHANGED_FILES}")
message(STATUS "补丁包含以下文件：")
foreach(changed_file IN LISTS NET_LAB_CHANGED_FILE_LINES)
    if(NOT "${changed_file}" STREQUAL "")
        message(STATUS "  ${changed_file}")
    endif()
endforeach()
message(STATUS "请按实验指导书在干净的初始版本上应用补丁并测试，再提交实验报告和 commit.patch。")
