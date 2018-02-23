FROM openshift/base-centos7

USER root

RUN yum -y install python \
    python-devel \
    python-pip \
    mercurial && yum clean all
    
#RUN yum -y install python-pip
RUN curl -k "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
RUN python get-pip.py
# Install dev cron
#RUN which pip
RUN pip install -e hg+https://bitbucket.org/dbenamy/devcron#egg=devcron

#ADD ./etc/crontab /cron/crontab

WORKDIR /usr/local/bin/

ADD skript.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/skript.sh
ADD ./cronjob /cron/crontab
RUN touch /var/log/cron.log 
RUN chmod 766 /var/log/cron.log 

USER 1001

CMD ["devcron.py", "/cron/crontab"]
