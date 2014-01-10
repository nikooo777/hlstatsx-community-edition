using System;
using System.Collections.Generic;
using System.Configuration;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;

namespace HLXCEServ
{
    public partial class HLXCEServ : ServiceBase
    {
        public HLXCEServ()
        {
            InitializeComponent();
        }
 
        string g_strHLXCEPath;
        string g_strPerlPath;
        ushort g_iDaemonCount;
        ushort g_iStartPort;
        uint g_iMaxRetries;

        List<Process> g_lprDaemons;
        List<StreamWriter> g_lswLogFiles;
        List<uint> g_liDaemonRetries;

        protected override void OnStart(string[] args)
        {
            g_strHLXCEPath = ConfigurationSettings.AppSettings["HLXCEPath"];
            g_strPerlPath = ConfigurationSettings.AppSettings["PerlPath"];
            g_iDaemonCount = Convert.ToUInt16(ConfigurationSettings.AppSettings["DaemonCount"]);
            g_iStartPort = Convert.ToUInt16(ConfigurationSettings.AppSettings["StartPort"]);
            g_iMaxRetries = Convert.ToUInt32(ConfigurationSettings.AppSettings["RetryCount"]);
            g_lprDaemons = new List<Process>(g_iDaemonCount);
            g_lswLogFiles = new List<StreamWriter>(g_iDaemonCount);
            g_liDaemonRetries = new List<uint>(g_iDaemonCount);

            for (ushort i = 0; i < g_iDaemonCount; i++)
            {
                g_liDaemonRetries.Add(0);
                g_lprDaemons.Add(null);
                g_lswLogFiles.Add(null);
            }

            string strLogPath = g_strHLXCEPath + @"\logs";
            if (!Directory.Exists(strLogPath))
            {
                EventLog.WriteEntry("\"" + g_strHLXCEPath + "\" does not exist; creating.", EventLogEntryType.Information);
                try
                {
                    Directory.CreateDirectory(strLogPath);
                }
                catch (Exception ex)
                {
                    EventLog.WriteEntry(ex.Message, EventLogEntryType.Error);
                    this.Stop();
                }
            }

            for (ushort i = 0; i < g_iDaemonCount; i++)
            {
                SetupStartDaemon(i, false);
            }
        }

        protected override void OnStop()
        {
            for (ushort i = 0; i < g_iDaemonCount; i++)
            {
                if (!g_lprDaemons[i].HasExited)
                {
                    g_lprDaemons[i].EnableRaisingEvents = false;
                    g_lprDaemons[i].Kill();
                }
                if (g_lswLogFiles[i] != null)
                {
                    g_lswLogFiles[i].Flush();
                    g_lswLogFiles[i].Close();
                }
            }
        }
        void HLXCE_OutputReceived(object sender, DataReceivedEventArgs e)
        {
            for (ushort i = 0; i < g_iDaemonCount; i++)
            {
                if (sender.Equals(g_lprDaemons[i]))
                {
                    g_lswLogFiles[i].WriteLine(e.Data);
                    if ((DateTime.Now.Second % 3) == 0)
                    {
                        g_lswLogFiles[i].Flush();
                    }
                    break;
                }
            }
        }
        void HLXCE_Exited(object sender, EventArgs e)
        {
            if (g_iDaemonCount > 1)
            {
                for (ushort i = 0; i < g_iDaemonCount; i++)
                {
                    if (sender.Equals(g_lprDaemons[i]))
                    {
                        if (++g_liDaemonRetries[i] > g_iMaxRetries)
                        {
                            int iRemainingDaemons = 0;
                            for (ushort j = 0; j < g_iDaemonCount; j++)
                            {
                                if (!g_lprDaemons[j].HasExited)
                                {
                                    iRemainingDaemons++;
                                }
                            }
                            if (iRemainingDaemons > 0)
                            {
                                string strEvMsg = String.Format("HLXCE Daemon on port {0:d} has exited unexpectedly with no retries left. {1:d} of {2:d} daemons still active.", g_iStartPort + i, iRemainingDaemons, g_iDaemonCount);
                                EventLog.WriteEntry(strEvMsg, EventLogEntryType.Warning);
                            }
                            else
                            {
                                EventLog.WriteEntry("All daemons have failed; exiting.", EventLogEntryType.Error);
                                this.Stop();
                            }
                        }
                        else
                        {
                            string strEvMsg = String.Format("HLXCE Daemon on port {0:d} has exited unexpectedly. {1:d} retries left.", g_iStartPort + i, g_iMaxRetries - g_liDaemonRetries[i]);
                            EventLog.WriteEntry(strEvMsg, EventLogEntryType.Warning);
                            SetupStartDaemon(i, true);
                        }
                    }
                }
            }
            else
            {
                EventLog.WriteEntry("HLXCE Daemon has exited unexpectedly", EventLogEntryType.Error);
                this.Stop();
            }
        }

        private void ExceptionFail(Exception ex)
        {
            EventLog.WriteEntry(ex.Message, EventLogEntryType.Error);
            this.Stop();
        }

        private void SetupStartDaemon(ushort iDaemonId, bool bRelaunch)
        {
            ushort iPort = (ushort)(g_iStartPort + iDaemonId);
            string strLogFilename;
            string strPerlArgs;

            if (g_iDaemonCount > 1)
            {
                strLogFilename = g_strHLXCEPath + @"\logs\" + iPort.ToString() + System.DateTime.Now.ToString("-yyyy-MM-dd-HH-mm-ss-ff") + ".log";
                strPerlArgs = g_strHLXCEPath + @"\hlstats.pl --port=" + iPort.ToString();
            }
            else
            {
                strLogFilename = g_strHLXCEPath + @"\logs\" + System.DateTime.Now.ToString("yyyy-MM-dd-HH-mm-ss-ff") + ".log";
                strPerlArgs = g_strHLXCEPath + @"\hlstats.pl";
            }

            if (bRelaunch)
            {
                g_lprDaemons[iDaemonId].Dispose();
                g_lswLogFiles[iDaemonId].Flush();
                g_lswLogFiles[iDaemonId].Close();
                g_lswLogFiles[iDaemonId].Dispose();
            }

            try
            {
                g_lswLogFiles[iDaemonId] = new StreamWriter(new FileStream(strLogFilename, System.IO.FileMode.OpenOrCreate));
            }
            catch (Exception ex)
            {
                ExceptionFail(ex);
            }

            g_lprDaemons[iDaemonId] = new Process();
            g_lprDaemons[iDaemonId].StartInfo.FileName = g_strPerlPath + @"\perl.exe";
            g_lprDaemons[iDaemonId].StartInfo.Arguments = strPerlArgs;
            g_lprDaemons[iDaemonId].StartInfo.WorkingDirectory = g_strHLXCEPath;
            g_lprDaemons[iDaemonId].StartInfo.CreateNoWindow = true;
            g_lprDaemons[iDaemonId].StartInfo.UseShellExecute = false;
            g_lprDaemons[iDaemonId].StartInfo.RedirectStandardOutput = true;
            g_lprDaemons[iDaemonId].StartInfo.RedirectStandardError = true;
            g_lprDaemons[iDaemonId].OutputDataReceived += new DataReceivedEventHandler(HLXCE_OutputReceived);
            g_lprDaemons[iDaemonId].EnableRaisingEvents = true;
            g_lprDaemons[iDaemonId].Exited += new EventHandler(HLXCE_Exited);
            try
            {
                g_lprDaemons[iDaemonId].Start();
                g_lprDaemons[iDaemonId].BeginOutputReadLine();
                g_lprDaemons[iDaemonId].BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                ExceptionFail(ex);
            }
        }
    }
}
