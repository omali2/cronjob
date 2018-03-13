FROM openshift/base-centos7

USER root

RUN yum -y --enablerepo=extras install epel-release
RUN yum -y install python \
    python-devel \
    python-pip \
    perl \
    perl-devel \
    mercurial && yum clean all
    
# Install dev cron
RUN pip install -e hg+https://bitbucket.org/dbenamy/devcron#egg=devcron

WORKDIR /usr/local/bin/

ADD ./cronjob /cron/crontab
ADD Automation.pl /usr/local/bin/
ADD liste.LST /usr/local/bin/
RUN chmod 755 /usr/local/bin/*
RUN touch /var/log/cron.log 
RUN chmod 766 /var/log/cron.log 

USER 1001

CMD ["devcron.py", "/cron/crontab"]
