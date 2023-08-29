import os
import sys
import venv
import pip
import site
import subprocess
import argparse
import importlib
import logging

cwd = os.getcwd()
parser = argparse.ArgumentParser()

# whether to be verbose
parser.add_argument('-v', '--verbose', action='store_true') 

# whether to run
#   'wrapper': the wrapper (default) which will run the service in a venv
#   'service': the service (after dependencies have been installed)
#   'raw':     the raw service (assumes all dependencies are installed)
parser.add_argument('--run', default='wrapper')

# the virtual environment path and directory name
parser.add_argument('--venv-path', default=cwd) 
parser.add_argument('--venv-name', default='venv')

# the gRPC port
parser.add_argument('--grpc-port', type=int, default=5252)

# the stdout encoding
parser.add_argument('--encoding', default=sys.stdout.encoding)

args = parser.parse_args()

# popen fails to pass the correct encoding?
if sys.stdout.encoding != args.encoding:
    sys.stdout.reconfigure(encoding=args.encoding)

# cleanup the virtual environment parameters
if args.venv_path is None or args.venv_path == "":
    args.venv_path = cwd
if not os.path.isabs(args.venv_path):
    args.venv_path = os.path.join(cwd, args.venv_path)

# begin
print()
print("*** UserCode Python Runtime ***")
print()

if args.verbose:
    print()
    print("encoding = %s" % sys.stdout.encoding)
    print("cwd = '%s'" % cwd)
    print("sys.path =")
    for item in list(sys.path):
        print("    - %s" % item)
    print("env =")
    for i, (k, v) in enumerate(os.environ.items()):
        print("    - %s = %s" % (k, v))
    print()

# a utility function that runs PIP
# because PIP programmatic API is... not to be used
def run_pip(*pip_args):

    pip_args = list(pip_args)

    print("exec: pip " + ' '.join(pip_args))
    pip_args[:0] = [ sys.executable, '-m', 'pip' ]
    pip_process = subprocess.Popen(pip_args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    pip_out, pip_err = pip_process.communicate()
    print("--")
    print(pip_out)
    print("--")
    print("rc=%d" % pip_process.returncode)
    print()
    return pip_process.returncode

# runs the wrapper
def wrapper():

    venv_dir = os.path.join(args.venv_path, args.venv_name)

    print("setting up virtual environment %s" % args.venv_name)
    print("in '%s'" % args.venv_path)

    # create the virtual environment, with PIP and upgraded dependencies
    venv.create(venv_dir, system_site_packages = True, clear = True, with_pip = True, upgrade_deps = True)

    # 'activate' the virtual environment and start again
    print("start process in virtual environment")
    
    # windows?
    python_path = os.path.join(venv_dir, 'Scripts', 'python.exe')
    if not os.path.isfile(python_path):
        # linux
        python_path = os.path.join(venv_dir, 'bin', 'python3')
    if not os.path.isfile(python_path):
        # muh?
        print("panic: '%s' does not exist" % python_path)
        sys.exit(1)
    
    script_path = __file__
    print("run '%s'" % script_path)
    os.chdir(venv_dir)
    print("in cwd = '%s'" % os.getcwd())
    print("with python = '%s'" % python_path)    

    # Windows has no support for exec*, spanws a child process and terminate the current one
    #os.execv(python_path, [python_path, work_path])

    process_args = [ python_path, script_path, '--run=service', '--grpc-port=%d' % args.grpc_port, '--encoding=%s' % sys.stdout.encoding ]
    if args.verbose:
        process_args.append('--verbose')
    process = subprocess.Popen(process_args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding=sys.stdout.encoding)
    print(f"forked process {process.pid}")
    print("--")
    while True:
        line = process.stdout.readline().strip()
        if line == '' and process.poll() is not None:
            break
        else:
            print(line)
    rc = process.poll()
    print("--")
    print("rc=%d" % rc)        
    print("exit")
    print()
    sys.exit(rc)

# runs the raw service
def service_raw():
    logging.basicConfig(stream=sys.stdout, format='%(asctime)s %(levelname)s [%(name)s] %(threadName)s - %(message)s', level=logging.INFO)
    print("start grpc server")
    import grpc_server # only here - grpc may be n/a when running the wrapper
    grpc_server.serve(args.grpc_port)

# runs the service with dependencies
def service():

    logging.basicConfig(stream=sys.stdout, format='%(asctime)s %(levelname)s [%(name)s] %(threadName)s - %(message)s', level=logging.INFO)

    # install some required dependencies
    print("install dependencies")
    reqd_protobuf = "4.24.0"
    reqd_grpcio = "1.57.0"
    rc = run_pip('install', 'protobuf==%s' % reqd_protobuf, 'grpcio==%s' % reqd_grpcio, '--upgrade')
    if rc != 0:
        sys.exit(1)

    # install custom dependencies
    home = os.path.dirname(__file__)
    requirements = os.path.join(home, "requirements.txt")
    if os.path.isfile(requirements):
        print("install '%s' dependencies" % requirements)
        rc = run_pip('install', '-r', requirements)
        if rc != 0:
            sys.exit(1)
    else:
        print("not found: '%s'" % requirements)

    print("list dependencies")
    rc = run_pip('list')
    if rc != 0:
        sys.exit(1)

    service_raw()

# run
if args.run == "wrapper":
    print("RUN: wrapper")
    wrapper()
elif args.run == "service":
    print("RUN: service with dependencies")
    service()
elif args.run == "raw":
    print("RUN: raw service")
    service_raw()
else:
    print("ERR: invalid 'run' value, must be 'wrapper', 'service' or 'raw'.")
    sys.exit(1)
    
