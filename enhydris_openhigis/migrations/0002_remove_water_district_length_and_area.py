# Generated by Django 2.2.4 on 2019-10-15 09:15

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [("enhydris_openhigis", "0001_initial")]

    operations = [
        migrations.RemoveField(model_name="waterdistrict", name="area"),
        migrations.RemoveField(model_name="waterdistrict", name="length"),
    ]