package org.example;

@FunctionalInterface
public interface FunctionThatThrows<T, R> {
    R apply(T t) throws Exception;
}
