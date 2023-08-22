homedir=getenv('HOME');
sharedir=fullfile(homedir,'work');
d=fullfile(sharedir,'gup'); [~,~]=mkdir(d)
gd=fullfile(sharedir,'gup','mygup'); [~,~]=mkdir(gd)
d=fullfile(sharedir,'results'); [~,~]=mkdir(d)
d=fullfile(sharedir,'mydata'); [~,~]=mkdir(d)
d=fullfile(homedir,'tmp'); [~,~]=mkdir(d)
%[~,~]=unix(['ln -s /shared_data ' homedir]);
addpath(gd,'/opt/guisdap/anal','/opt/guisdap/init')
clear homedir sharedir d gd
startup
