
#pragma once

#include "Core/RTTI.h"
#include "Core/Ref.h"
#include <string>
#include <type_traits>

namespace pepper {

    template <typename T, typename Base>
    concept IsA = std::is_base_of_v<Base, T>;

    template <typename T>
    concept HasToString = requires(T t) {
                              { t.toString() } -> std::same_as<std::string>;
                          };

} // namespace pepper
