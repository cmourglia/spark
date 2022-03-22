#pragma once

#include <beard/containers/array.h>

#include <functional>

template <typename T>
class Property {
 public:
  using Callback = std::function<void(const T&)>;
  using Callbacks = beard::array<Callback>;

  Property() = default;
  Property(T data)  // NOLINT The implicit constructor is intentional here
      : m_Data{std::move(data)} {}

  Property(const Property& other) = default;
  Property(Property&& other) noexcept = default;

  ~Property() = default;

  Property<T>& operator=(T data) {
    m_Data = std::move(data);
    Notify();
    return *this;
  }

  Property<T>& operator=(const Property& other) {
    m_Data = other.m_Data;

    const_cast<Property&>(other).Subscribe([this](const T& data) {
      this->m_Data = data;
      this->Notify();
    });

    Notify();

    return *this;
  }

  Property<T>& operator=(Property&& other) noexcept = default;

 private:
  T m_Data;
  Callbacks m_Callbacks;

  void Subscribe(Callback callback) { m_Callbacks.Add(std::move(callback)); }

  void Notify() {
    for (auto&& callback : m_Callbacks) {
      callback(m_Data);
    }
  }
};