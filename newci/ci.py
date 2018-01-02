#!/usr/bin/env python
"""module docstring here"""

# System modules
from queue import Queue
from threading import Thread
import time
import subprocess
import os
from os import listdir
from os.path import isfile, join
import sys
import json
import logging
from multiprocessing import Lock
import requests
from datetime import datetime

# Set up some global variables
WORK_QUEUE = Queue()
JOBS_RUNNING = 0
POLL_IGNORE_COMMITS = dict()
BUSY_SHAS = dict()
STOPPED = False
LOCK = Lock()
API_TOKEN=""

class CiWorker(object):
    """ CI Worker doc """
    def __init__(self, busy_key, outdir, template, test, repo, commit, ref, delegate):
        self.template = template
        self.test = test
        self.outdir = outdir
        self.script = test["script"]
        self.repo = repo
        self.commit = commit
        self.status_commit = commit
        self.ref = ref
        self.delegate = delegate
        self.busy_key = busy_key
        self.thread_index = -1
        self.pr_number = 0
        self.is_authorized = False
        self.prepared = False


    def verify_ref(self, ref, commit):
        global API_TOKEN
        url = "%s/git/%s" % (self.repo["status_api"], ref)
        api_user = self.repo["api_user"]
        res = requests.get(url, auth=(api_user, API_TOKEN))
        print(url)
        print("verify %s/%s -? %s\n:%s" % (self.ref, self.commit, res.status_code, res.text))

        if res.status_code != 200:
            return False
        return commit in res.text

    def prepare(self, status_api_url, approved_authors):
        global API_TOKEN
        if self.prepared:
            return
        self.prepared = True
        self.is_authorized = self.verify_ref(self.ref, self.commit)
        api_user = self.repo["api_user"]
        
        if not self.is_authorized:
            return
        tmp = self.ref.split("/")
        pr_number = tmp[2]
        if len(tmp) == 4 and tmp[0] == "refs" and tmp[1] == "pull":
            self.is_authorized = False
            url = "%s/pulls/%s" % (self.repo["status_api"], pr_number)
            res = requests.get(url, auth=(api_user, API_TOKEN))
            if res.status_code != 200:
                print("Git api get failed: [%s] (%s)" % (url, res.status_code))
                return False, ""
            json = res.json()
            if json["state"] != "open":
                print("pr state is not open %s" % json["state"])
                return

            # note that mergable can also be null. which means 'unknown' for now.
            # we'll just go ahead and try the tests in that case.
            if  json["mergeable"] is False:
                print("pr is not mergeable, makes no sense to check")
                return

            pr_author = json["user"]["login"]
            self.is_authorized = pr_author in self.repo["pr_approved_authors"]
            if not self.is_authorized:
                print("pr author not authorized: %s" % pr_author)
            head_sha = json["head"]["sha"]
            self.status_commit = head_sha

            # sanity check
            if self.status_commit != self.commit:
                if tmp[3] != "merge":
                    raise Exception('status updated unexpectedly!')
        url = "%s/commits/%s" % (self.repo["status_api"], self.commit)
        res = requests.get(url, auth=(api_user, API_TOKEN))
        if res.status_code != 200:
            print("Git api get failed: [%s] (%s)" % (url, res.status_code))
            return False, ""
        json = res.json()
        present = datetime.now()
        if (present - datetime.strptime(json["commit"]["committer"]["date"], "%Y-%m-%dT%H:%M:%SZ")).days >= 1:
            print("commit is too old is too old")
            return False
    

    def run(self, thread_index):
        """ run docstr """
        # the sleeps are for a silly reason: we use timestamps to sort, 
        # and these have a 1 second granularity on the filesystem, or
        # so it seems at the moment.
        self.thread_index = thread_index
        time.sleep(1)
        self.set_status("check")

        if not self.is_authorized:
            self.set_status("unauth")
            del BUSY_SHAS[self.busy_key]
            return
        time.sleep(1)
        self.set_status("start")

        if self.delegate(self):
            self.set_status("success")
        else:
            self.set_status("fail")
        del BUSY_SHAS[self.busy_key]

    def set_status(self, state):
        """ udpate the status files, and github if applicable """
        key = "%s-%s" % (self.template, self.test["name"])
        touch("%s/%s.%s" % (self.outdir, key, state))
        print('touch("%s/%s.%s")' % (self.outdir, key, state))

        git_state = ""
        git_context_sha = "push"

        self.prepare(self.repo["status_api"], self.repo["pr_approved_authors"])

        if self.commit != self.status_commit:
            git_context_sha = "pr"

        git_context = "pagespeed_ci/%s/%s/%s" % (git_context_sha, self.test["name"], self.template)
        # pending, success, error, or failure
        if state == "queued":
            git_state = "pending"
        elif state == "unauth":
            git_state = "error"
        elif state == "fail":
            git_state = "failure"
        elif state == "success":
            git_state = "success"

        api_user = self.repo["api_user"]
        global API_TOKEN
        if git_state and self.repo["update_git_status"]:
            print("update git:  %s -> %s (%s)" % (self.status_commit, git_context, git_state))
            url = "%s/statuses/%s" % (self.repo["status_api"], self.status_commit)
            data = """"state": "{git_state}",
  "target_url": "http://ci.onpagespeed.com/build/{commit}",
  "description": "{git_state}",
  "context": "{git_context}"
""".format(git_state=git_state, git_context=git_context, commit=self.commit)
            res = requests.post(url, data=("{%s}" % data), auth=(api_user, API_TOKEN))
            if res.status_code != 201:
                print("status updated failed for url %s (%s)" % (url, res.status_code))

    def already_ran(self):
        key = "%s-%s" % (self.template, self.test["name"])
        return os.path.exists("%s/%s.success" % (self.outdir, key)) or \
            os.path.exists("%s/%s.fail" % (self.outdir, key)) or \
            os.path.exists("%s/%s.unauth" % (self.outdir, key)) or \
            os.path.exists("%s/done" % (self.outdir))

    def to_str(self):
        """ Returns string representation of the CI worker """
        return "%s %s %s %s" % (self.template, self.script, self.commit, self.ref)

def load_configuration(path):
    """ loads the program configuration """
    with open(path, 'r') as content_file:
        raw_content = content_file.read()
        parsed = json.loads(raw_content)
        return parsed

def load_token(path):
    """ loads the program configuration """
    with open(path, 'r') as content_file:
        return content_file.read()

    
class Repo(object):
    """ Holds state and defines CI for a repo """
    def __init__(self, repo, refs_to_ignore, test_delegate):
        self.repo = repo
        self.refs_to_ignore = refs_to_ignore
        self.test_delegate = test_delegate

def queue_consumer_worker(thread_index, queue):
    """This is the worker thread function.
    It processes items in the queue one after
    another.  These daemon threads go into an
    infinite loop, and only exit when
    the main thread ends.
    """
    global JOBS_RUNNING
    while not STOPPED:
        popped = queue.get()
        JOBS_RUNNING = JOBS_RUNNING + 1
        popped.run(thread_index)
        JOBS_RUNNING = JOBS_RUNNING -1
        queue.task_done()

def start_workers(number_of_workers):
    """ starts the workers for executing the CI on a commit """
    for i in range(number_of_workers):
        worker = Thread(target=queue_consumer_worker, args=(i, WORK_QUEUE,))
        worker.setDaemon(True)
        worker.start()

def touch(fname, times=None):
    with open(fname, 'a'):
        os.utime(fname, times)

def git_poll_repo_worker(repos, interval_seconds, ci_out):
    """ loops to call git ls-remote for all repos """
    while not STOPPED:
        for repo in repos:
            if "enabled" in repo and repo["enabled"] == False:
                continue
            giruri = repo["gituri"]
            command = "git ls-remote -q %s" % giruri
            with open("/tmp/ls-remote.in", "w") as fstdin:
                with open("ls-remote-%s.log" % repo["id"], "w") as fstdout:
                    process = subprocess.Popen(command.split(), stdout=fstdout, stderr=subprocess.STDOUT, stdin=fstdin)
            print("Got %s" % giruri)
            process.wait()
            if process.returncode:
                print("ls-remote failed: %d" % process.returncode)
            else:
                with open("ls-remote-%s.log" % repo["id"], "r") as fstdout:
                    reflist = fstdout.readlines()
                for line in filter(lambda x: len(x.split("\t")) == 2, reflist):
                    line=line.strip()
                    commit, ref = line.split("\t")
                    if not commit in POLL_IGNORE_COMMITS and not is_ignored_ref(ref):
                        outdir = "%s/%s/%s" % (ci_out, repo["id"], commit)
                        if not os.path.exists(outdir):
                            os.makedirs(outdir)
                        for test in repo["tests"]:
                            for template in test["templates"]:
                                key = "%s-%s-%s-%s" % (repo["id"], template, test["script"], commit)
                                work_item = CiWorker( \
                                    key, outdir, template, test, repo, commit, ref, test_runner)
                                if not work_item.already_ran():
                                    if key in BUSY_SHAS:
                                        continue
                                    else:
                                        BUSY_SHAS[key] = True
                                    work_item.set_status("queued")
                                    WORK_QUEUE.put(work_item)

        time.sleep(interval_seconds)

def setup_git_repo_polling(repos, interval_seconds, ci_out):
    """ Starts a thread to poll the repos using git ls-remote """
    worker = Thread(target=git_poll_repo_worker, args=(repos,interval_seconds,ci_out))
    worker.setDaemon(True)
    worker.start()

def test_runner(self):
    """ Test execution, runs an the thread pool """
    #print "executing test_runner ---> %s" % self.to_str()
    #command = "./create_vm.sh --template %s --name ci-number-%d --script %s --ref %s --commit %s" % \
    #    (self.template, self.thread_index, self.script, self.ref, self.commit)
    command = self.script.format(branch=self.commit, ref=self.ref)
    
    print("execute: %s" % command)
    fs_name = "%s/%s-%s" % (self.outdir, self.template, self.test["name"])

    with open("%s.stdin.txt" % fs_name, "w") as fstdin:
        with open("%s.stdout.txt" % fs_name, "w") as fstdout:
            self.prepared = False
            self.prepare(self.repo["status_api"], self.repo["pr_approved_authors"])
            if not self.is_authorized:
                print("abort test run for %s"  % command)
                fstdout.write("abort test run for %s"  % command)
                return True
            process = subprocess.Popen(command.split(), stdout=fstdout, stderr=subprocess.STDOUT, stdin=fstdin)

    process.wait()
    return process.returncode == 0

def run_program():
    """tst"""
    global STOPPED
    global API_TOKEN
    conf = load_configuration("ci.conf")
    API_TOKEN = load_token(".token")
    load_ignore_lists()

    # TODO(oschaaf): we shouldn't mark them all as done.
    # ideally, we only mark those that have all tests executed
    for project_dir in os.listdir(conf["ci_out"]):
        project_dir = os.path.join(conf["ci_out"], project_dir)
        if os.path.isdir(project_dir):
            for commit_dir in os.listdir(project_dir):
                touch(os.path.join(project_dir, commit_dir, "done"))

    worker_pool_size = int(conf["worker_pool_size"])
    if worker_pool_size < 0:
        worker_pool_size = 2

    poll_interval_seconds = int(conf["poll_interval_seconds"])
    if poll_interval_seconds < 0:
        poll_interval_seconds = 60

    start_workers(worker_pool_size)
    setup_git_repo_polling(conf["repos"], poll_interval_seconds, conf["ci_out"])

    print("CI started, %s workers. Enter q <enter> to quit" % worker_pool_size)

    global JOBS_RUNNING

    while not STOPPED:
        line = ""
        for line in sys.stdin:
            line = line.strip()
            if line in ["q", "Q"]:
                STOPPED = True
                print("stopping")
                break
            else:
                print("%d active jobs, %d queued. (press q followed by <enter> to quit)" % (JOBS_RUNNING, WORK_QUEUE.qsize()))

    while JOBS_RUNNING > 0:
        print('*** CI Stopping, waiting for %d jobs to wrap up: ' % JOBS_RUNNING)
        time.sleep(1)

    # TODO(oschaaf): we shouldn't mark them all as done.
    # ideally, we only mark those that have all tests executed
    for project_dir in os.listdir(conf["ci_out"]):
        project_dir = os.path.join(conf["ci_out"], project_dir)
        if os.path.isdir(project_dir):
            for commit_dir in os.listdir(project_dir):
                touch(os.path.join(project_dir, commit_dir, "done"))

    WORK_QUEUE.join()

    print('*** Done')

def load_ignore_lists():
    """ Load the to-be-ignored commits from the files in ignore/ """
    onlyfiles = [f for f in listdir("ignore/") if isfile(join("ignore/", f))]
    for file in onlyfiles:
        if "#" in file or "~" in file:
            continue
        print("load ignorelist %s" % file)
        with open("ignore/%s" % file, 'r') as content_file:
            content = content_file.read()
            reflist = content.split('\n')
            for line in filter(lambda x: len(x.split("\t")) == 2, reflist):
                commit, ref = line.split("\t")
                POLL_IGNORE_COMMITS[commit] = True

def is_ignored_ref(ref):
    """ Defines some refs that we don't want to handle """
    if ref == "HEAD":
        return True
    if ref.endswith("^{}"):
        return True
    return False

run_program()
