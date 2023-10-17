package org.example;

import java.util.concurrent.Callable;

import java.util.function.Function;

import picocli.CommandLine;

public class SubmitCommand implements Callable<Integer> {

    private final FunctionThatThrows<SubmitCommand, Integer> execute;

    public SubmitCommand(FunctionThatThrows<SubmitCommand, Integer> execute) {
        this.execute = execute;
    }

    @Override
    public Integer call() throws Exception {
        submitCode = codePath != null;
        runtime.isContainer = runtime.runtimeImage != null;
        runtime.isPassthru = runtime.runtimeAddress != null;
        return execute.apply(this);
    }

    static class RuntimeArgs {

        @CommandLine.Option(names = "--runtime-image", description = "The runtime image.", required = true)
        public String runtimeImage;

        public boolean isContainer;

        @CommandLine.Option(names = "--runtime-address", description = "The passthru runtime address.", required = true)
        public String runtimeAddress;

        public boolean isPassthru;
    }

    @CommandLine.ArgGroup(exclusive = true, multiplicity = "1")
    public RuntimeArgs runtime;

    // alas, picocli cannot express that, if --runtime-image is provided, then --registry-auth can be provided
    // picocli is kinda limited in its support for inter-dependent options - so the group above specifies that
    // either --runtime-image OR --runtime-address MUST be provided - but --registry-auth is free-floating...
    @CommandLine.Option(names = "--registry-auth", description = "The Docker auth JSON for the runtime image registry.", required = false)
    public String registryAuth;

    @CommandLine.Option(names = { "--code-path" }, description = "The optional path to the code directory.")
    public String codePath;

    public boolean submitCode;

    @CommandLine.Option(names = { "--secrets-path" }, description = "The path to the secrets directory.")
    public String secretsPath;

    @CommandLine.Option(names = { "--submit-secrets" }, description = "Whether to submit secrets as a resource.")
    public boolean submitSecrets;
}
