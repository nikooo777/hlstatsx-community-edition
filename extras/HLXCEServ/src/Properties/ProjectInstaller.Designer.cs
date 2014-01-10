namespace HLXCEServ
{
    partial class ProjectInstaller
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary> 
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Component Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.HLXCEServProcessInstaller1 = new System.ServiceProcess.ServiceProcessInstaller();
            this.HLXCEServInstaller = new System.ServiceProcess.ServiceInstaller();
            // 
            // HLXCEServProcessInstaller1
            // 
            this.HLXCEServProcessInstaller1.Password = null;
            this.HLXCEServProcessInstaller1.Username = null;
            // 
            // HLXCEServInstaller
            // 
            this.HLXCEServInstaller.Description = "Windows Service Control for HLX:CE";
            this.HLXCEServInstaller.DisplayName = "HLXCEServ";
            this.HLXCEServInstaller.ServiceName = "HLXCEServ";
            // 
            // ProjectInstaller
            // 
            this.Installers.AddRange(new System.Configuration.Install.Installer[] {
            this.HLXCEServProcessInstaller1,
            this.HLXCEServInstaller});

        }

        #endregion

        private System.ServiceProcess.ServiceProcessInstaller HLXCEServProcessInstaller1;
        private System.ServiceProcess.ServiceInstaller HLXCEServInstaller;
    }
}