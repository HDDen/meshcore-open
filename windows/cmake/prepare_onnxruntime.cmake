set(MCO_ONNXRUNTIME_VERSION "1.22.0")
set(MCO_ONNXRUNTIME_PACKAGE
    "onnxruntime-win-x64-${MCO_ONNXRUNTIME_VERSION}")
get_filename_component(
    MCO_ONNXRUNTIME_CACHE_DIR
    "${CMAKE_CURRENT_LIST_DIR}/../.cache/onnxruntime"
    ABSOLUTE)
set(MCO_ONNXRUNTIME_ROOT
    "${MCO_ONNXRUNTIME_CACHE_DIR}/${MCO_ONNXRUNTIME_PACKAGE}")
set(MCO_ONNXRUNTIME_DLL "${MCO_ONNXRUNTIME_ROOT}/lib/onnxruntime.dll")
set(MCO_ONNXRUNTIME_LIB "${MCO_ONNXRUNTIME_ROOT}/lib/onnxruntime.lib")
set(MCO_ONNXRUNTIME_HEADER
    "${MCO_ONNXRUNTIME_ROOT}/include/onnxruntime_cxx_api.h")

set(MCO_ONNXRUNTIME_DLL_SHA256
    "579b636403983254346a5c1d80bd28f1519cd1e284cd204f8d4ff41f8d711559")
set(MCO_ONNXRUNTIME_LIB_SHA256
    "ab00cba665b186c0d29df9c575d34fd2bcc8f9b9ecae997f81610d07b2fc8ebc")
set(MCO_ONNXRUNTIME_HEADER_SHA256
    "7606924bbc40810a72fca54d8aff75c9564908301241eb835bc1814a3aee4ad8")

function(mco_onnxruntime_cache_is_valid output_variable)
  set(is_valid TRUE)
  foreach(required_file
          "${MCO_ONNXRUNTIME_DLL}"
          "${MCO_ONNXRUNTIME_LIB}"
          "${MCO_ONNXRUNTIME_HEADER}")
    if(NOT EXISTS "${required_file}")
      set(is_valid FALSE)
    endif()
  endforeach()

  if(is_valid)
    file(SHA256 "${MCO_ONNXRUNTIME_DLL}" actual_dll_sha256)
    file(SHA256 "${MCO_ONNXRUNTIME_LIB}" actual_lib_sha256)
    file(SHA256 "${MCO_ONNXRUNTIME_HEADER}" actual_header_sha256)
    if(NOT actual_dll_sha256 STREQUAL MCO_ONNXRUNTIME_DLL_SHA256 OR
       NOT actual_lib_sha256 STREQUAL MCO_ONNXRUNTIME_LIB_SHA256 OR
       NOT actual_header_sha256 STREQUAL MCO_ONNXRUNTIME_HEADER_SHA256)
      set(is_valid FALSE)
    endif()
  endif()

  set(${output_variable} ${is_valid} PARENT_SCOPE)
endfunction()

mco_onnxruntime_cache_is_valid(cache_is_valid)
if(NOT cache_is_valid)
  file(REMOVE_RECURSE "${MCO_ONNXRUNTIME_ROOT}")
  file(MAKE_DIRECTORY "${MCO_ONNXRUNTIME_CACHE_DIR}")

  set(download_url
      "https://github.com/microsoft/onnxruntime/releases/download/v${MCO_ONNXRUNTIME_VERSION}/${MCO_ONNXRUNTIME_PACKAGE}.zip")
  set(download_file
      "${MCO_ONNXRUNTIME_CACHE_DIR}/${MCO_ONNXRUNTIME_PACKAGE}.zip.part")
  file(REMOVE "${download_file}")

  message(STATUS "Downloading ONNX Runtime into persistent Windows cache")
  file(DOWNLOAD
       "${download_url}"
       "${download_file}"
       SHOW_PROGRESS
       TLS_VERIFY ON
       TIMEOUT 600
       INACTIVITY_TIMEOUT 45
       STATUS download_status
       LOG download_log)
  list(GET download_status 0 download_code)
  list(GET download_status 1 download_message)
  if(NOT download_code EQUAL 0)
    file(REMOVE "${download_file}")
    message(FATAL_ERROR
      "ONNX Runtime download failed: ${download_message}\n"
      "Download it manually from:\n${download_url}\n"
      "and extract it under:\n${MCO_ONNXRUNTIME_CACHE_DIR}")
  endif()

  message(STATUS "Extracting ONNX Runtime into persistent Windows cache")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${download_file}"
    WORKING_DIRECTORY "${MCO_ONNXRUNTIME_CACHE_DIR}"
    RESULT_VARIABLE extract_result
    ERROR_VARIABLE extract_error)
  file(REMOVE "${download_file}")
  if(NOT extract_result EQUAL 0)
    file(REMOVE_RECURSE "${MCO_ONNXRUNTIME_ROOT}")
    message(FATAL_ERROR "ONNX Runtime extraction failed: ${extract_error}")
  endif()

  # The 340 MB debug database is not needed for application builds.
  file(REMOVE "${MCO_ONNXRUNTIME_ROOT}/lib/onnxruntime.pdb")
  mco_onnxruntime_cache_is_valid(cache_is_valid)
  if(NOT cache_is_valid)
    file(REMOVE_RECURSE "${MCO_ONNXRUNTIME_ROOT}")
    message(FATAL_ERROR
      "Downloaded ONNX Runtime files failed integrity verification")
  endif()
endif()

message(STATUS "Using cached ONNX Runtime: ${MCO_ONNXRUNTIME_ROOT}")

# Force flutter_onnxruntime's CMake project down its system-runtime branch so
# it does not start its own unbounded download in build/plugins/.
set(USE_SYSTEM_ONNXRUNTIME ON CACHE BOOL
    "Use the application's persistent ONNX Runtime cache" FORCE)
set(ONNXRUNTIME_ROOT_DIR "${MCO_ONNXRUNTIME_ROOT}" CACHE PATH
    "Persistent ONNX Runtime root" FORCE)
set(ONNXRUNTIME_LIBRARY "${MCO_ONNXRUNTIME_LIB}" CACHE FILEPATH
    "Persistent ONNX Runtime import library" FORCE)
set(ONNXRUNTIME_INCLUDE_DIR "${MCO_ONNXRUNTIME_ROOT}/include" CACHE PATH
    "Persistent ONNX Runtime headers" FORCE)

# The plugin only bundles the DLL in its download branch. Seed the variable so
# its final PARENT_SCOPE export also bundles the cached system-runtime DLL.
set(flutter_onnxruntime_bundled_libraries "${MCO_ONNXRUNTIME_DLL}")
