using System;
using System.Collections.Generic;
using System.Configuration;
using System.Diagnostics;
using System.IO;
using System.Net.Mail;
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
		ProcessPriorityClass g_priority;
		bool g_bStartProxy;
		
		List<Process> g_lprDaemons;
		List<StreamWriter> g_lswLogFiles;
		List<uint> g_liDaemonRetries;
		
		SmtpClient g_Mailer;
		ushort g_iNotifyLvl = 0;
		
		protected override void OnStart(string[] args)
		{
			g_strHLXCEPath = ConfigurationManager.AppSettings["HLXCEPath"];
			g_strPerlPath = ConfigurationManager.AppSettings["PerlPath"];
			g_iDaemonCount = Convert.ToUInt16(ConfigurationManager.AppSettings["DaemonCount"]);
			g_iStartPort = Convert.ToUInt16(ConfigurationManager.AppSettings["StartPort"]);
			g_iMaxRetries = Convert.ToUInt32(ConfigurationManager.AppSettings["RetryCount"]);
			g_lprDaemons = new List<Process>(g_iDaemonCount);
			g_lswLogFiles = new List<StreamWriter>(g_iDaemonCount);
			g_liDaemonRetries = new List<uint>(g_iDaemonCount);
			g_priority = GetPriorityFromString(ConfigurationManager.AppSettings["Priority"]);
			g_iNotifyLvl = Convert.ToUInt16(ConfigurationManager.AppSettings["EmailNotificationLvl"]);
			string proxstart = ConfigurationManager.AppSettings["StartProxy"];
			g_bStartProxy = (proxstart == "yes" || proxstart == "1");
			
			if (g_iNotifyLvl > 0)
			{
				SetupEmail();
			}
			
			if (!File.Exists(g_strPerlPath + @"\perl.exe"))
			{
				DoError(String.Format("Failed to find {0:s}. Check your PerlPath setting in HLXCEServ.exe.config", g_strPerlPath + @"\perl.exe"));
				this.Stop();
			}
			
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
					DoError(ex.Message);
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
					g_lprDaemons[i].CloseMainWindow();
					g_lprDaemons[i].WaitForExit();
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
		void HLXCE_ProxyExited(object sender, EventArgs e)
		{
			DoError("Proxy is no longer running; exiting.");
			this.Stop();
		}
		void HLXCE_Exited(object sender, EventArgs e)
		{
			if (g_iDaemonCount <= 1)
			{
				DoError("HLXCE Daemon has exited unexpectedly");
				this.Stop();
				return;
			}
			 
			for (ushort i = 0; i < g_iDaemonCount; i++)
			{
				if (!sender.Equals(g_lprDaemons[i]))
				{
					continue;
				}
					 
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
						DoWarning(strEvMsg);
					}
					else
					{
						DoError("All daemons have failed; exiting.");
						this.Stop();
					}
				}
				else
				{
					string strEvMsg = String.Format("HLXCE Daemon on port {0:d} has exited unexpectedly. {1:d} retries left.", g_iStartPort + i, g_iMaxRetries - g_liDaemonRetries[i]);
					DoWarning(strEvMsg);
					SetupStartDaemon(i, true);
				}
				break;
			}
		}
		
		private void ExceptionFail(Exception ex)
		{
			DoError(ex.Message);
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
				g_lswLogFiles[iDaemonId].Flush();
				g_lswLogFiles[iDaemonId].Close();
			}
			
			try
			{
				g_lswLogFiles[iDaemonId] = new StreamWriter(new FileStream(strLogFilename, System.IO.FileMode.OpenOrCreate));
			}
			catch (Exception ex)
			{
				ExceptionFail(ex);
			}
			
			if (g_bStartProxy)
			{
				g_lprDaemons[iDaemonId] = new Process();
				g_lprDaemons[iDaemonId].StartInfo.FileName = g_strPerlPath + @"\perl.exe";
				g_lprDaemons[iDaemonId].StartInfo.Arguments = g_strHLXCEPath + @"\hlstats-proxy.pl";
				g_lprDaemons[iDaemonId].StartInfo.WorkingDirectory = g_strHLXCEPath;
				g_lprDaemons[iDaemonId].StartInfo.CreateNoWindow = true;
				g_lprDaemons[iDaemonId].StartInfo.UseShellExecute = false;
				g_lprDaemons[iDaemonId].EnableRaisingEvents = true;
				g_lprDaemons[iDaemonId].Exited += new EventHandler(HLXCE_ProxyExited);
				g_lprDaemons[iDaemonId].Start();
				g_lprDaemons[iDaemonId].PriorityClass = g_priority;
			}
			
			g_lprDaemons[iDaemonId] = new Process();
			g_lprDaemons[iDaemonId].StartInfo.FileName = g_strPerlPath + @"\perl.exe";
			g_lprDaemons[iDaemonId].StartInfo.Arguments = strPerlArgs;
			g_lprDaemons[iDaemonId].StartInfo.WorkingDirectory = g_strHLXCEPath;
			g_lprDaemons[iDaemonId].StartInfo.CreateNoWindow = true;
			g_lprDaemons[iDaemonId].StartInfo.UseShellExecute = false;
			g_lprDaemons[iDaemonId].StartInfo.RedirectStandardOutput = true;
			g_lprDaemons[iDaemonId].StartInfo.RedirectStandardError = true;
			g_lprDaemons[iDaemonId].ErrorDataReceived += new DataReceivedEventHandler(HLXCE_OutputReceived);
			g_lprDaemons[iDaemonId].OutputDataReceived += new DataReceivedEventHandler(HLXCE_OutputReceived);
			g_lprDaemons[iDaemonId].EnableRaisingEvents = true;
			g_lprDaemons[iDaemonId].Exited += new EventHandler(HLXCE_Exited);
			try
			{
				g_lprDaemons[iDaemonId].Start();
				g_lprDaemons[iDaemonId].BeginOutputReadLine();
				g_lprDaemons[iDaemonId].BeginErrorReadLine();
				g_lprDaemons[iDaemonId].PriorityClass = g_priority;
			}
			catch (Exception ex)
			{
				ExceptionFail(ex);
			}
		}
		
		private void SetupEmail()
		{
			string username = ConfigurationManager.AppSettings["EmailUsername"];
			string password = ConfigurationManager.AppSettings["EmailPassword"];
			g_Mailer = new SmtpClient(ConfigurationManager.AppSettings["EmailHost"], Convert.ToInt32(ConfigurationManager.AppSettings["EmailPort"]));
			if (g_Mailer != null && username != "" && password != "")
			{
				g_Mailer.Credentials = new System.Net.NetworkCredential(username, password);
			}
		}
		
		private void DoWarning(string message)
		{
			EventLog.WriteEntry(message, EventLogEntryType.Warning);
			if (g_Mailer != null && g_iNotifyLvl >= 2)
			{
				g_Mailer.Send(new MailMessage(ConfigurationManager.AppSettings["EmailFrom"], ConfigurationManager.AppSettings["EmailTo"], "HLXCEServ Warning", "Warning from HLXCEServ:\n\n" + message + "\n"));
			}
		}
		
		private void DoError(string message)
		{
			EventLog.WriteEntry(message, EventLogEntryType.Error);
			if (g_Mailer != null && g_iNotifyLvl >= 1)
			{
				g_Mailer.Send(new MailMessage(ConfigurationManager.AppSettings["EmailFrom"], ConfigurationManager.AppSettings["EmailTo"], "HLXCEServ Error", "Error from HLXCEServ:\n\n" + message + "\n"));
			}
		}
		
		private ProcessPriorityClass GetPriorityFromString(string sPriority)
		{
			sPriority = sPriority.ToLower();
			switch (sPriority)
			{
				case "idle":
					return ProcessPriorityClass.Idle;
				case "belownormal":
					return ProcessPriorityClass.BelowNormal;
				case "abovenormal":
					return ProcessPriorityClass.AboveNormal;
				case "high":
					return ProcessPriorityClass.High;
				case "realtime":
					return ProcessPriorityClass.RealTime;
			}
			return ProcessPriorityClass.Normal;
		}
	}
}
