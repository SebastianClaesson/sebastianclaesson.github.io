---
title: Azure DevOps Pipeline Output
date: 2022-09-03 06:55:01
categories: [Azure DevOps, Colored Output]
tags: [powershell,azure devops,output,ascii,color,pipeline]     # TAG names should always be lowercase
---
### Ever thought about visualising the output of your pipeline with color in Azure DevOps?

I wanted to create my custom [What-if deployment - PowerShell](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-what-if?tabs=azure-powershell) as there is an issue with the Azure Firewall rules being scrambled and giving false-positives for changes at each run, rendering the output almost unreadable.

There's a built-in commands in Azure DevOps that can be used to produce colored output, sections and groups.
Read more here: [Azure DevOps Formatting Commands](https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=powershell#formatting-commands)

These formatting commands are great! The output renders such as:
![Azure DevOps formatting commands](/assets/images/2022/2022-09-03-2.png)

This acheives what we would like to see, however there's only one little annoying thing, that is that there's no informational (or success/verbose) command that we can use.

The green output is called "Section", which does not start with the ##[section] which makes it harder to read in the log output of Azure DevOps in my opinion. I would simply like to have my error text in the color of my choosing and without any prefixes.

The first thought that came to mind is that perhaps the [write-host command with ForegroundColor](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-host?view=powershell-7.2#example-4-write-with-different-text-and-background-colors) might do the trick.
However the render output from that command in Azure DevOps ends up like this:
![write-host](/assets/images/2022/2022-09-03-1.png)
Which is not what we were looking for.

I decided to test if the ANSI color codes would be render as documented here: [ANSI Colors](https://en.wikipedia.org/wiki/ANSI_escape_code#3-bit_and_4-bit).
To test this out, we create a yaml pipeline for example the one below.
```yaml
steps:
- pwsh: |
    $FormattedString = '{0}{1}{2}' -f "$([char]27)[32`m", 'Testing', "$([char]27)[0m"
    Write-output $FormattedString
```
And checking the rendered output in Azure DevOps you can see the following:
![ANSI Output](/assets/images/2022/2022-09-03-3.png)
We can see that it says 'Testing' in green!
Checking the raw log we can also see this:
![ANSI Output - Raw log](/assets/images/2022/2022-09-03-4.png)
This means that the Azure DevOps portal do render ANSI colors, which is great!

After reviewing the wikipedia page regarding ANSI colors, we can also see that if we increase each color code by 10, it should also hight light the text with the color as a background color.
![Azure DevOps background and foreground colored](/assets/images/2022/2022-09-03-5.png)

Seems we're onto something! 

We're able to output colored text as we want, without any prefixes making it easier for a human to read.
In this case I've also grouped the output in two sections, "ForegroundColored" and "BackgroundColored".

This is a great feature if you want to gather output in groups, making it easier to navigate the output and just expand the groups you are interested in.

As I stated in the start, I've used this to build my own custom what-if deployment to render the Azure DevOps pipeline output humanly readable.

I'll create a blogpost series on that but for now the code for the cemo pipeline and PowerShell function can be found on my github: https://github.com/SebastianClaesson/AzureDevopsPipelineColorDemo

A big thanks for reading and feel free to drop any comments below!