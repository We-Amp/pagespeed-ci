using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.IO;

namespace MPSCI.Models
{
    public class Commit
    {
        public string project { get; set; }
        public string sha { get; set; }
        public DateTime date { get; set; }
        public List<FileInfo> files { get; set; }
        public string tag;
        public string Status
        {
            get
            {
                List<string> tests = new List<string>();
                foreach(var f in files)
                {
                    if (f.Extension == ".queued")
                    {
                        tests.Add(f.Name.Substring(0, f.Name.Length - ".queued".Length));
                    }
                }

                string s = "";
                string state = "";
                string style = "";

                foreach (var test in tests)
                {
                    state = "";
                    style = " style='color:{0}' ";

                    foreach (var f in files)
                    {
                        if (f.Name.StartsWith(test))
                        {
                            if (f.Extension == ".success")
                            {
                                state = "success";
                                style = string.Format(style, "green");
                            } else if (f.Extension == ".unauth")
                            {
                                state = "blocked";
                                style = string.Format(style, "silver");
                            }
                            else if (f.Extension == ".fail")
                            {
                                state = "failed";
                                style = string.Format(style, "red");
                            }
                            else if (f.Extension == ".queued")
                            {
                                state = "queued";
                            } else if (f.Extension == ".start")
                            {
                                state = "started";
                                style = string.Format(style, "navy");
                            }
                        }
                        if (state != "") 
                        {
                            s += "<a " + style + " href = '/stream/" + project + "/" + sha +"/" + test + "'>" + test + " (" + state + " @ " + f.LastWriteTime.ToLocalTime() + ")</a><br/>\n";
                            break;
                        }
                    }
                }
                return s;
            }
        }
    }
}
