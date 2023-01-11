//
// Created by justi on 1/11/2023.
//

#pragma once

#if defined(_WIN32)
#    define SUPPORT_API __declspec(dllexport)
#else
#    define SUPPORT_API __attribute__((visibility("default")))
#endif
