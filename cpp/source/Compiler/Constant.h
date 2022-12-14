#pragma once

#include "Compiler/Value.h"

class Constant : public Value {};

class ConstantInt : public Constant {};

class ConstantFloat : public Constant {};

class ConstantString : public Constant {};
