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
        runtime.isProcess = runtime.processName != null;
        return execute.apply(this);
    }

    static class RuntimeArgs {

        @CommandLine.Option(names = "--runtime-image", description = "The runtime image.", required = true)
        public String runtimeImage;

        public boolean isContainer;

        @CommandLine.Option(names = "--runtime-address", description = "The passthru runtime address.", required = true)
        public String runtimeAddress;

        public boolean isPassthru;

        @CommandLine.Option(names = "--process-name", description = "The process runtime process name.", required = true)
        public String processName;

        public boolean isProcess;
    }

    @CommandLine.ArgGroup(exclusive = true, multiplicity = "1")
    public RuntimeArgs runtime;

    @CommandLine.Option(names = { "--code-path" }, description = "The optional path to the code directory.")
    public String codePath;

    public boolean submitCode;

    @CommandLine.Option(names = { "--secrets-path" }, description = "The path to the secrets directory.")
    public String secretsPath;

    @CommandLine.Option(names = { "--submit-secrets" }, description = "Whether to submit secrets as a resource.")
    public boolean submitSecrets;

    // alas, picocli cannot express that, if --runtime-image is provided, then --registry-auth can be provided
    // picocli is kinda limited in its support for inter-dependent options - so twe specify that either
    // --runtime-image OR --runtime-address OR --process-name MUST be provided - but the rest below is
    // free-floating...
    @CommandLine.Option(names = "--registry-auth", description = "The Docker auth JSON for the runtime image registry.", required = false)
    public String registryAuth;

    @CommandLine.Option(names = "--process-path", description = "The process runtime process path.", required = false)
    public String processPath;

    @CommandLine.Option(names = "--process-port", description = "The process runtime process port.", required = false)
    public int processPort = 5252;

    @CommandLine.Option(names = "--process-work-directory", description = "The process runtime process work directory.", required = false)
    public String workDirectory;

    @CommandLine.Option(names = "--process-arg", description = "The process runtime process work arg (can be repeated).", required = false)
    public String[] processArgs;
}
