cmake_minimum_required(VERSION 2.6)

PROJECT(cgi-io C)

INCLUDE(CheckFunctionExists)

FIND_LIBRARY(ubox NAMES ubox)
FIND_LIBRARY(json-c NAMES json-c)

ADD_DEFINITIONS(-Os -Wall -Werror -Wextra --std=gnu99 -g3)
ADD_DEFINITIONS(-Wno-unused-parameter -Wmissing-declarations)

SET(CMAKE_SHARED_LIBRARY_LINK_C_FLAGS "")

IF(APPLE)
  INCLUDE_DIRECTORIES(/opt/local/include)
  LINK_DIRECTORIES(/opt/local/lib)
ENDIF()

SET(LIB_SOURCES multipart_parser.c util.c)
ADD_LIBRARY(cgi-lib STATIC ${LIB_SOURCES})

ADD_EXECUTABLE(cgi-io main.c)
TARGET_LINK_LIBRARIES(cgi-io cgi-lib ${ubox} ${json-c})

IF(UNIT_TESTING)
  ADD_DEFINITIONS(-DUNIT_TESTING)
  ENABLE_TESTING()
  ADD_SUBDIRECTORY(tests)

  IF(CMAKE_C_COMPILER_ID STREQUAL "Clang")
    ADD_LIBRARY(cgi-lib-san SHARED ${LIB_SOURCES})
    TARGET_COMPILE_OPTIONS(cgi-lib-san PRIVATE -g -fno-omit-frame-pointer -fsanitize=undefined,address,leak -fno-sanitize-recover=all)
    TARGET_LINK_OPTIONS(cgi-lib-san PRIVATE -fsanitize=undefined,address,leak)
    TARGET_LINK_LIBRARIES(cgi-lib-san ${ubox} ${json-c})

    ADD_EXECUTABLE(cgi-io-san main.c)
    TARGET_COMPILE_OPTIONS(cgi-io-san PRIVATE -g -fno-omit-frame-pointer -fsanitize=undefined,address,leak -fno-sanitize-recover=all)
    TARGET_LINK_OPTIONS(cgi-io-san PRIVATE -fsanitize=undefined,address,leak)
    TARGET_LINK_LIBRARIES(cgi-io-san cgi-lib-san ${ubox})
  ENDIF()
ENDIF()

INSTALL(TARGETS cgi-io RUNTIME DESTINATION sbin)
