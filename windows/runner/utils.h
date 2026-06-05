#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#if __has_include(<string>)

#include <string>
#include <vector>

void CreateAndAttachConsole();

std::string Utf8FromUtf16(const wchar_t* utf16_string);

std::vector<std::string> GetCommandLineArguments();

#endif  // __has_include(<string>)

#endif  // RUNNER_UTILS_H_
