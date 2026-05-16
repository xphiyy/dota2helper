using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string guiScript = Path.Combine(dir, "AutoAcceptor-GUI.ps1");

        if (!File.Exists(guiScript))
        {
            MessageBox.Show(
                "AutoAcceptor-GUI.ps1 was not found next to this launcher.",
                "Dota Auto Acceptor",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        string args = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + guiScript + "\"";

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = args,
            WorkingDirectory = dir,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        try
        {
            Process.Start(startInfo);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Could not launch the GUI:\n\n" + ex.Message,
                "Dota Auto Acceptor",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }
}
