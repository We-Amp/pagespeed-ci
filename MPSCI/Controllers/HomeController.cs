using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using System.IO;
using MPSCI.Models;
using System.Text;

namespace MPSCI.Controllers
{

    public class HomeController : Controller
    {
        public IActionResult Index()
        {
            string cidir = "../newci/ci-out/";
            System.IO.DirectoryInfo di = new System.IO.DirectoryInfo(cidir);
            System.IO.DirectoryInfo dx = new System.IO.DirectoryInfo("../newci/");
            List<string> refs = new List<string>();

            foreach (var f in dx.GetFiles())
            {
                if (f.Name.StartsWith("ls-remote"))
                {
                    refs.AddRange(System.IO.File.ReadLines(f.FullName));
                }
            }
            var refByCommit = new Dictionary<string, string>();
            char[] tab = new char[] { '\t' };
            foreach(string r in refs){
                var tmp = r.Split(tab);
                if (tmp.Length != 2) continue;
                var sha = tmp[0];
                if (!refByCommit.ContainsKey(tmp[0]))
                {
                    refByCommit.Add(tmp[0], tmp[1]);
                } else
                {
                    refByCommit[tmp[0]] = refByCommit[tmp[0]] + "," + tmp[1];
                }
            }
            var commits = new List<Commit>();
            foreach(var d  in di.GetDirectories())
            {
                foreach (var sd in d.GetDirectories())
                {
                    var commit = new Commit();
                    commit.project = d.Name;
                    commit.sha = sd.Name;
                    if (!refByCommit.TryGetValue(commit.sha, out commit.tag))
                    {
                        commit.tag = "";
                    }
                    commit.date = sd.CreationTime;
                    commit.files = new List<FileInfo>();
                    commit.files.AddRange(sd.GetFiles().Where(f => f.Name != "done").OrderByDescending(f => f.LastWriteTime).ToList());
                    if (commit.files.Count() > 0)
                    {
                        commits.Add(commit);
                    }
                }
            }
            commits = commits.OrderByDescending(c => c.files.First().LastWriteTime).ToList();
            return View(commits);
        }


        static string ReadTail(string filename, int size)
        {
            try
            {
                using (FileStream fs = System.IO.File.Open(filename, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    long pos = 0;
                    long msize = size > fs.Length ? fs.Length : size;
                    try { 
                        pos = fs.Seek(-1 * msize, SeekOrigin.End);
                    } catch
                    {
                    }
                    byte[] bytes = new byte[msize];
                    fs.Read(bytes, 0, (int)msize);
                    // Convert bytes to string
                    string s = Encoding.ASCII.GetString(bytes);
                    // or string s = Encoding.UTF8.GetString(bytes);
                    // and output to console
                    return s;
                }
            }
            catch(IOException)
            {
                return "Couldn't read file";
            }
        }

        static string GetLog(string file, int size)
        {
            string s = ReadTail(file, size);
            char[] split = new char[] { System.Environment.NewLine[0] };
            var tmp = s.Split(split).Reverse().ToList();
            string sout = string.Join(System.Environment.NewLine, tmp);
            return sout;
        }

        [Route("stream/{project}/{sha}/{test}")]
        public IActionResult About(string project, string sha, string test)
        {
            ViewData["Message"] = "Your application description page"  + project + "/" + sha + "/" + test;
            ViewData["project"] = project;
            ViewData["sha"] = sha;
            ViewData["test"] = test;

            string stdout = GetLog("../newci/ci-out/" + project + "/" + sha + "/" + test + ".stdout.txt", 1024 * 16);
            if (HttpContext.Request.Method == "POST")
            {
                var ddd = "../newci/ci-out/" + project + "/" + sha + "/";
                foreach (var f in Directory.GetFiles(ddd))
                {
                    var sub = f.Substring(ddd.Length);
                    if (sub.IndexOf(test) == 0 || sub == "done")
                    {
                        System.IO.File.Delete(f);
                    }
                }
                Response.Redirect("?" + HttpContext.Request.QueryString);
            }
            return View((object)stdout);
        }


        public IActionResult Contact()
        {
            ViewData["Message"] = "Your contact page.";

            return View();
        }

        public IActionResult Error()
        {
            return View();
        }
    }
}
