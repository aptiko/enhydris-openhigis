# Generated by Django 2.2.7 on 2019-11-05 15:12

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [("enhydris_openhigis", "0007_imported_id")]

    operations = [
        migrations.AlterField(
            model_name="drainagebasin",
            name="imported_id",
            field=models.IntegerField(unique=True),
        ),
        migrations.AlterField(
            model_name="riverbasindistrict",
            name="imported_id",
            field=models.IntegerField(unique=True),
        ),
    ]
