import os
import sys
import venv
import pip
import site
import subprocess
import argparse
import grpc_server
import importlib
import logging

cwd = os.getcwd()

parser = argparse.ArgumentParser()
parser.add_argument('-v', '--verbose', action='store_true')
parser.add_argument('-p', '--process', action='store_true')
parser.add_argument('--venv-path', default=cwd)
parser.add_argument('--venv-name', default='venv')
parser.add_argument('--grpc-port', type=int, default=5252)
parser.add_argument('--encoding', default=sys.stdout.encoding)
args = parser.parse_args()

# popen fails to pass the correct encoding?
if sys.stdout.encoding != args.encoding:
    sys.stdout.reconfigure(encoding=args.encoding)

venv_path = args.venv_path
venv_name = args.venv_name
is_process = args.process
is_wrapper = not is_process
is_verbose = args.verbose
grpc_port = args.grpc_port

if venv_path is None or venv_path == "":
    venv_path = cwd
if not os.path.isabs(venv_path):
    venv_path = os.path.join(cwd, venv_path)

print()
if is_process:
    print("*** usercode runtime process ***")
else:
    print("*** usercode runtime wrapper ***")
print()

if is_verbose:
    print("encoding = %s" % sys.stdout.encoding)
    print("cwd = '%s'" % cwd)
    print("sys.path =")
    for item in list(sys.path):
        print("    - %s" % item)
    print("env =")
    for i, (k, v) in enumerate(os.environ.items()):
        print("    - %s = %s" % (k, v))

def wrapper():

    venv_dir = os.path.join(venv_path, venv_name)

    print("setting up virtual environment %s" % venv_name)
    print("in '%s'" % venv_path)

    # create the virtual environment, with PIP and upgraded dependencies
    venv.create(venv_dir, True, True, with_pip = True, upgrade_deps = True)

    # 'activate' the virtual environment and start again
    print("start process in virtual environment")
    python_path = os.path.join(venv_dir, 'Scripts', 'python.exe')
    script_path = __file__
    print("run '%s'" % script_path)
    os.chdir(venv_dir)
    print("in cwd = '%s'" % os.getcwd())
    print("with python = '%s'" % python_path)    
    if not os.path.isfile(python_path):
        print("panic: '%s' does not exist" % python_path)
        sys.exit(1)

    # Windows has no support for exec*, spanws a child process and terminate the current one
    #os.execv(python_path, [python_path, work_path])

    process_args = [ python_path, script_path, '--process', '--grpc-port=%d' % grpc_port, '--encoding=%s' % sys.stdout.encoding ]
    if is_verbose:
        process_args.append('--verbose')
    process = subprocess.Popen(process_args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding=sys.stdout.encoding)
    print(f"forked process {process.pid}")
    print("--")
    while True:
        line = process.stdout.readline().strip()
        #try:
        #    line = line.decode('utf-8')
        #except UnicodeDecodeError:
        #    print("wtf?")
        #    raise
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

def service():
    print("start grpc server")
    grpc_server.serve(grpc_port)

def process():

    logging.basicConfig(stream=sys.stdout, format='%(asctime)s %(levelname)s [%(name)s] %(threadName)s - %(message)s', level=logging.INFO)

    # install some required dependencies
    print("install dependencies")
    reqd_protobuf = "4.24.0"
    reqd_grpcio = "1.57.0"
    # meh - pip programmatic API is ?!
    #pip.main(['install', 'protobuf==%s' % reqd_protobuf, 'grpcio==%s' % reqd_grpcio])
    rc = run_pip('install', 'protobuf==%s' % reqd_protobuf, 'grpcio==%s' % reqd_grpcio, '--upgrade')
    if rc != 0:
        sys.exit(1)

    # find usercode module - without loading it! - but really we should do better
    module_name = 'usercode-functions'
    try:
        #module = importlib.import_module(module_name)
        spec = importlib.util.find_spec(module_name)
    except ImportError as e:
        raise RuntimeError("Cannot import module '%s'" % module_name, e)
    if spec is None:
        print("failed to find module '%s'" % module_name)
    #print(spec)
    #print("found usercode-functions at '%s'" % os.path.abspath(module.__file__))
    #print("found usercode-functions at '%s'" % os.path.abspath(spec.submodule_search_locations[0]))
    print("found usercode-functions at '%s'" % os.path.abspath(spec.origin))
    home = os.path.dirname(spec.origin) # better way to find it?

    # install custom dependencies
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

    service()

if is_process:
    process()
else:
    wrapper()